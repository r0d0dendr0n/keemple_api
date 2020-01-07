# keemple_api
CLI interface for Keemple/OBLO smarthouse solution written in Perl.

# License

IDGAF what you do with it or what it does to you. It's your problem, not mine. You can tell me if you do something cool, though.

# Installation

cpan install File::Slurp;

cpan install Selenium::Firefox;

cpan install Selenium::Remote::WDKeys;

cpan install Text::Trim;

You must have Firefox binary available in PATH. To run without X server, use Xvfb.

If you are able to run this in any other environments than Linux, let me know.

# Running

./KeempleScrapper.pl <conf_path> <device_name> <switch_index_1..n> <state_1|0_(true=1)>
  
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
* True headless mode (browser window visible only with some "--debug" option.)
