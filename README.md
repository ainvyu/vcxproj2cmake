## Required modules:
* Try::Tiny;
* XML::TreePP;
* XML::TreePP::XMLPath;
* Text::Xslate;
* Readonly
* autobox::Core

### how to install the modules?
Usually you start cpan in your shell:
```
sudo apt-get install perl
cpan 
install Try::Tiny;
install XML::TreePP;
install XML::TreePP::XMLPath;
install Text::Xslate;
install Readonly
install autobox::Core
```
or directly fron the shell
```
cpan Try::Tiny;
cpan XML::TreePP;
cpan XML::TreePP::XMLPath;
cpan Text::Xslate;
cpan Readonly
cpan autobox::Core
```

## Usage

    perl vcxproj2cmake.pl <vcxproj path> <target configuration>
