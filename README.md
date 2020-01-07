# keemple_api
CLI interface for Keemple/OBLO smarthouse solution written in Perl.

# Installation

cpan install File::Slurp;
cpan install Selenium::Firefox;
cpan install Selenium::Remote::WDKeys;
cpan install Text::Trim;

You must have Firefox binary available in PATH. To run without X server, use Xvfb.

If you are able to run this in any other environments than Linux, let me know.

# Running

./KeempleScrapper.pl <conf path> <device name> <switch index 1..n> <state 1|0 (true=1)>
./KeempleScrapper.pl ~/.keempleAPI.conf 'światło salon' 2 1

# Development

Pull requests are welcome.

# TODO

* Use Getopts...
* Validate login.
* Check if the gateway offline.
* Selecting a gateway via command line.
* Standalone server which would keep a persistent session and allow queued commands execution.
* Reading values (not limited to switches!).
