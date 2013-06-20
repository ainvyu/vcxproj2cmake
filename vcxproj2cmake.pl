#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';
use Readonly;

use autobox::Core;
use Try::Tiny;
use XML::TreePP;
use XML::TreePP::XMLPath;
use Text::Xslate;
use Data::Dumper;
use FindBin;

my $filepath    = $ARGV[0]
    || die "Usage: $FindBin::Script <vcxproj path> <target configuration>";
my $target_conf = $ARGV[1]
    || die "Usage: $FindBin::Script <vcxproj path> <target configuration>";

my $filters_path = $filepath . '.filters';

my $vcxproj_xml  = XML::TreePP->new()->parsefile($filepath);
my $vcxproj_filters_xml  = XML::TreePP->new()->parsefile($filters_path);
my $target = $vcxproj_xml->{Project}->{PropertyGroup}->[0]->{RootNamespace};
my $target_prop = get_target_property($target_conf,
                                      get_propertys($vcxproj_xml));
my $filenode_ref = get_file_node($vcxproj_xml);
my $item_def_ref = get_item_def_group($vcxproj_xml,
                                      $target_prop->{-Condition});
my %filters = get_filters($vcxproj_filters_xml);

make($filenode_ref, $item_def_ref, %filters);

sub get_filters {
    my ($vcxproj_filters_xml) = @_;
    my %filters = ();
  
    my @itemgroups = @{$vcxproj_filters_xml->{Project}->{ItemGroup}};
    
    # first itemgroup is list of filters
    for my $filter (@{$itemgroups[0]->{Filter}}) {
        my $filtername = $filter->{-Include};
        my @files = ();
        @{$filters{$filtername}} = @files;
    }
    
    # second itemgroup contains sorce files filter information
    for my $clcompile (@{$itemgroups[1]->{ClCompile}}) {
        my $filename = $clcompile->{-Include};
        my $filter = $clcompile->{Filter};
        push @{$filters{$filter}}, $filename;
    }
    
    # third itemgroup contains header files filter information
    for my $clinclude (@{$itemgroups[2]->{ClInclude}}) {
        my $filename = $clinclude->{-Include};
        my $filter = $clinclude->{Filter};
        push @{$filters{$filter}}, $filename;
    }
    
    # fourth itemgroup contains filter information for files that should not compiled (like readme)
    
    # fifth itemgroup contains recources filter
    
    # remove empty arrays
    my @toDelete;
    for my $filter (keys %filters) {
        my @filterfiles = @{$filters{$filter}};
        if (scalar @filterfiles == 0) {
            push @toDelete, $filter;
        }
    }
    #delete @filters{@toDelete};
    
    return %filters;
}

sub get_target_property {
    my ($target_conf, @property_groups) = @_;
    my $target_prop;
    for my $property (@property_groups) {
        if ($property->{-Condition} =~ m{$target_conf}) {
            $target_prop = $property;
            last;
        }
    }

    return $target_prop;
}

sub get_item_def_group {
    my ($vcxproj_xml, $cond) = @_;
    my $tppx = new XML::TreePP::XMLPath;

    # my $xpath = '/Project/ItemDefinitionGroup[@Condition="'.$cond.'"]';
    # warn $xpath;
    # my $item_def_ref = $tppx->filterXMLDoc($vcxproj_xml, $xpath);
    my $item_def_ref;
    for my $item_def ($tppx->filterXMLDoc($vcxproj_xml,
                                          '/Project/ItemDefinitionGroup')) {
        if ($item_def->{-Condition} eq $cond) {
            $item_def_ref = $item_def;
            last;
        }
    }

    return $item_def_ref;
}

sub get_propertys {
    my ($vcxproj_xml) = @_;
    my $property_node_ref;

    my $tppx = new XML::TreePP::XMLPath;
    my @property_groups
        = $tppx->filterXMLDoc($vcxproj_xml,
                              '/Project/PropertyGroup[@Label="Configuration"]');

    return @property_groups;
}

sub get_file_node {
    my ($vcxproj_xml) = @_;
    my @itemgroups = @{$vcxproj_xml->{Project}->{ItemGroup}};
    my $filenode_ref;
    for my $itemgroup (@itemgroups) {
        next if (defined $itemgroup->{-Label}
                     && $itemgroup->{-Label} eq 'ProjectConfigurations');

        for my $nodename (keys %{$itemgroup}) {
            my @nodes;

            if (ref($itemgroup->{$nodename}) eq 'HASH') {
                push @nodes, $itemgroup->{$nodename};
            } else {
                @nodes = @{$itemgroup->{$nodename}};
            }

            for my $node (@nodes) {
                unless (defined $node->{ExcludedFromBuild}
                            && $node->{ExcludedFromBuild}->{-Condition} eq $target_prop->{-Condition}) {
                    push @{$filenode_ref->{$nodename}}, $node->{-Include};
                }
            }
        }
    }

    return $filenode_ref;
}

sub make {
    my ($filenode_ref, $item_def_ref, %filters) = @_;

    my @srcs    = @{$filenode_ref->{ClCompile}};
    my @headers = @{$filenode_ref->{ClInclude}};
    my $add_dir = $item_def_ref->{ClCompile}->{AdditionalIncludeDirectories};
    $add_dir =~ s{\\}{/}g;
    my @includes =
        grep { $_ ne '%(AdditionalIncludeDirectories)' }
            split ';', $add_dir;

    my $def = $item_def_ref->{ClCompile}->{PreprocessorDefinitions};
    # add prefix -D. example> -DSHP
    my @defs =
        map { "-D$_"; }
            grep { $_ ne '%(PreprocessorDefinitions)' }
                split ';', $def;

    my $add_dep = $item_def_ref->{Link}->{AdditionalDependencies};
    $add_dep =~ s{\\}{/}g;
    my @deps =
        grep { $_ ne '%(AdditionalDependencies)' }
            split ';', $add_dep;

    warn Dumper(@includes);

    my $tx = Text::Xslate->new(
        syntax    => 'TTerse',
        path      => [ '.', '.' ],
    );

    # render source groups
    my $render_source_groups = '';
    for my $filter (keys %filters) {        
        my @files = @{$filters{$filter}};
        $filter =~ s/\\/\\\\/g;
        my %vars = (
            flter => $filter,
            files => +(join "\n\t", @files),
        );
        warn Dumper(%vars);
        
        try {
            my $render = $tx->render( 'CMakeSourceGroup.tx', \%vars );
            $render_source_groups = $render_source_groups . $render;
        } catch {
            print "caught error: $_\n";
        };        
    }


    my %vars = (
        type            => $target_prop->{ConfigurationType},
        charset         => $target_prop->{CharacterSet},
        target          => $target,
        def             => +(join "\n\t", @defs),
        lib             => +(join "\n\t", @deps),
        include         => +(join "\n\t", @includes),
        src             => +(join "\n\t", @srcs),
        header          => +(join "\n\t", @headers),
        source_groups   => Text::Xslate::Util::mark_raw($render_source_groups),
    );

    warn Dumper(%vars);

    my $render_text;
    try {
        $render_text = $tx->render( 'CMakeLists.tx', \%vars );
    } catch {
        print "caught error: $_\n";
    };

    open my $cmakelists_file, '>', 'CMakeLists.txt';
    print {$cmakelists_file} $render_text;
}
