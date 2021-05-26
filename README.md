# sm-gungame-fof

![Build Status](https://github.com/CrimsonTautology/sm-gungame-fof/workflows/Build%20plugins/badge.svg?style=flat-square)
[![GitHub stars](https://img.shields.io/github/stars/CrimsonTautology/sm-gungame-fof?style=flat-square)](https://github.com/CrimsonTautology/sm-gungame-fof/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/CrimsonTautology/sm-gungame-fof.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-gungame-fof/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/CrimsonTautology/sm-gungame-fof.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-gungame-fof/pulls)
[![GitHub All Releases](https://img.shields.io/github/downloads/CrimsonTautology/sm-gungame-fof/total.svg?style=flat-square&logo=github&logoColor=white)](https://github.com/CrimsonTautology/sm-gungame-fof/releases)

GunGame for Fistful of Frags


## Requirements
* [SourceMod](https://www.sourcemod.net/) 1.10 or later


## Installation
Make sure your server has SourceMod installed.  See [Installing SourceMod](https://wiki.alliedmods.net/Installing_SourceMod).  If you are new to managing SourceMod on a server be sure to read the '[Installing Plugins](https://wiki.alliedmods.net/Managing_your_sourcemod_installation#Installing_Plugins)' section from the official SourceMod Wiki.

Download the latest [release](https://github.com/CrimsonTautology/sm-gungame-fof/releases/latest) and copy the contents of `addons` to your server's `addons` directory. 

SteamWorks extension is also required for the server to run correctly. Get the latest build for either windows or linux here: https://users.alliedmods.net/~kyles/builds/SteamWorks/. Again, copy the contents of `addons` to your servers `addons` directory. 

It is recommended to restart your server after installing.

To confirm the plugin is installed correctly, on your server's console type:
```
sm plugins list
```

## Usage


### Commands
NOTE: All commands can be run from the in-game chat by replacing `sm_` with `!` or `/`.  For example `sm_rtv` can be called with `!rtv`.

| Command | Accepts | Values | SM Admin Flag | Description |
| --- | --- | --- | --- | --- |
| `fof_gungame_restart` | None | None | Generic | Force restart the round |
| `fof_gungame_reload_cfg` | None | None | Config | Force a reload of the configuration file |
| `fof_gungame_scores` | None | None | Root | (debug) List player score values to console |


### Console Variables

| Command | Accepts | Values | Description |
| --- | --- | --- | --- |
| `fof_gungame_enabled` | boolean | 0-1 | Whether or not Gun Game is enabled |
| `fof_gungame_config` | string | file path | Location of the Gun Game configuration file |
| `fof_gungame_fists` | boolean | 0-1 | Whether or not to allow fists in game.  Killing someone with fists will reduce their level |
| `fof_gungame_heal` | float | 0-100 | Amount of health player recieves when ranking up |
| `fof_gungame_equip_delay` | float | 0-999 | (deprecated) Seconds before giving new equipment on spawn |
| `fof_gungame_drunkness` | float | 0-999 | (deprecated) Amount of "drunkness" player recieves when ranking up |
| `fof_gungame_logfile` | string | file path | (deprecated) Location of the Gun Game log file |


## Compiling
If you are new to SourceMod development be sure to read the '[Compiling SourceMod Plugins](https://wiki.alliedmods.net/Compiling_SourceMod_Plugins)' page from the official SourceMod Wiki.

You will need the `spcomp` compiler from the latest stable release of SourceMod.  Download it from [here](https://www.sourcemod.net/downloads.php?branch=stable) and uncompress it to a folder.  The compiler `spcomp` is located in `addons/sourcemod/scripting/`;  you may wish to add this folder to your path.

Once you have SourceMod downloaded you can then compile using the included [Makefile](Makefile).

```sh
cd sm-gungame-fof
make SPCOMP=/path/to/addons/sourcemod/scripting/spcomp
```

Other included Makefile targets that you may find useful for development:

```sh
# compile plugin with DEBUG enabled
make DEBUG=1

# pass additonal flags to spcomp
make SPFLAGS="-E -w207"

# install plugins and required files to local srcds install
make install SRCDS=/path/to/srcds

# uninstall plugins and required files from local srcds install
make uninstall SRCDS=/path/to/srcds
```


## Contributing

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## License
[GNU General Public License v3.0](https://choosealicense.com/licenses/gpl-3.0/)


## Acknowledgements

* [Leonardo's Original FoF Gun Game plugin](https://gitlab.com/xpenia/gamemods/fof-gungame)
