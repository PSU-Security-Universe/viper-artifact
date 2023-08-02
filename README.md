# viper-artifact

Scripts for artifaction of [Viper](https://github.com/PSU-Security-Universe/viper). For four new data-only attacks on sqlite and v8, please refer to [data-only-attacks](https://github.com/PSU-Security-Universe/data-only-attacks).

## Testing Environment

* Ubuntu 20.04.6 LTS
* Clang 6.0.1-14
* Python 3.8.10
* Graphviz 2.43.0
* WLLVM 1.3.1

## Quick Start

Please set the environment variable `VIPER` to the location of the Viper repository, for example: 

``` bash
git clone https://github.com/PSU-Security-Universe/viper.git
git clone https://github.com/PSU-Security-Universe/viper-artifact.git
export VIPER=$(pwd)/viper
```

We provide scripts (`build.sh`) to automatically test most programs (including both branch flipping and corruptibility assessment). You can execute shell scripts directly (e.g., `bash build.sh`) and check the results.
> NOTE: some programs require special handling so it's better to follow the instructions listed in `build.sh` and run the commands one by one. 
* for branch flipping, the result is located at `log/flip_result`.
* for corruptibility assessment, the result is located in `dot/` folder.
