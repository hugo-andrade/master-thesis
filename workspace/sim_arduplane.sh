#!/bin/bash

####
## ArduPlane Software In The Loop (SITL)
##
## Hugo Andrade de Oliveira
## 05/01/2016
##
## Lab. Robótica e Inteligência Computacional
## Instituto Militar de Engenharia (IME)
####
VERSION=0.0.5

# REQUIRED
#
# export PATH=$PATH:<workspace>/jsbsim/src
# export PATH=$PATH:<workspace>/ardupilot/Tools/autotest
# export PATH=/usr/lib/ccache:$PATH
#
# JSBSIM
# ===============================
# cd jsbsim
# git pull
# ./autogen.sh --enable-libraries
# make
# ===============================
#
# <workspace>
#         |- sim_arduplane.sh
#         |- /ardupilot
#         |- /jsbsim
#
# See more in: <http://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html>
#
# 28/08/2016 | Changelog
# For multiple instance Arduplane, JSBSim correction for Flight Gear socket
# -> SITL_State.cpp line 102
# -> change:
#         fg_socket.connect(127.0.0.1, 5503 + _instance*10);
#
# For multiplayer FlightGear in localhost, see more in:
#   http://fgms.freeflightsim.org/install_guide.html

########################
## CHANGE VARs
########################

ARDUPILOT_BASEDIR="<WORKSPACE FULL PATH>/ardupilot"
LOCATION=-22.904997,-43.16309,5,179.6  # SBRJ as default location
AIRCRAFT_NAME="<AIRCRAFT NAME>"
MISSION_NAME="<MISSION NAME>"

########################

#
# Default Constants
#
INSTANCE=0
DEFAULT_PARAMS=
MAVPROXY_PORT_MAST=5760
MAVPROXY_PORT_SITL=5501
MAVPROXY_ADDR_OUT1=0
MAVPROXY_ADDR_OUT2=0
MAVPROXY_CONSOLE=0
REBUILD=0
NUM_PROCS=4
START_FG=0
FG_MULT=0
WIPE_EEPROM=0
WIND=0
VIBRATION=0

# Help Content
usage(){
cat <<EOF

Usage: sim_arduplane.sh [options]

ArduPlane Options:
        -l   Set custom start location [latitude,longitude,altitude,heading]
        -w   wipe EEPROM and reload parameters
        -I   [Instance]
             Instance of simulator (default 0)
        -R   Build/Rebuild ArduPlane.elf
        -J   [NUM_PROCS]
             Number of processors to use during build
             (default: 4)
        -p   [File path]
             Custom params to load in ArduPlane
             (default: ardupilot/Tools/autotest/ArduPlane.parm)
        -W   Add random wind direction and speed, in SITL
        -V   Add random acceleration noise, to testing the effects of vibration
        -v   Show version
        -h   Show help

FlightGear Options:
        -F   Start FlightGear simulator
        --FM Start FlightGear with multiplayer option
             Assuming that exist a local FGMS running in [localhost:6000]

Mavproxy Options:
        -c   Start Mavproxy console
        --mpo1
             Add Mavproxy addr output [localhost:14550]
        --mpo2
             Add Mavproxy addr extra output [localhost:14551]

EOF
}

# read the options
TEMP=`getopt -o l:wRI:J:Fvp:WVhc --long mpo1,mpo2,cmd:,FM,version,help -n 'sim_arduplane.sh' -- "$@"` || exit 1
eval set -- "$TEMP"

# parse options
# by http://www.bahmanm.com/blogs/command-line-options-how-to-parse-in-bash-using-getopt
while true; do
  case "$1" in
    -l )
  LOCATION="$2" ;
  shift 2
  ;;
    -w )
  WIPE_EEPROM=1 ;
  shift 1
  ;;
    -R )
  REBUILD=1 ;
  shift 1
  ;;
    -I )
  INSTANCE="$2" ;
  shift 2
  ;;
    -J )
  REBUILD=1 ;
  NUM_PROCS="$2" ;
  shift 2
  ;;
    -p )
  DEFAULT_PARAMS="$2" ;
  shift 2
  ;;
    -p )
  WIND=1 ;
  shift 1
  ;;
    -F )
  START_FG=1 ;
  shift 1
  ;;
    --FM )
  FG_MULT=1 ;
  shift 1
  ;;
    --mpo1 )
  MAVPROXY_ADDR_OUT1="127.0.0.1:14550" ;
  shift 1
  ;;
    --mpo2 )
  MAVPROXY_ADDR_OUT2="127.0.0.1:14551" ;
  shift 1
  ;;
    -W )
  WIND=1 ;
  shift 1
  ;;
    -V )
  VIBRATION=1 ;
  shift 1
  ;;
    -v | --version )
  printf "sim_arduplane version \"$VERSION\" \nHugo Andrade <hugo.slip@gmail.com>\n" >&2;
  exit 1
  ;;
    -h | --help )
  usage;
  exit 1
  ;;
    -c )
  MAVPROXY_CONSOLE=1 ;
  shift 1
  ;;
    -- )
	shift;
	break
	;;
    *)
	echo "Internal error!" ;
	exit 1
	;;
  esac
done

#
# Header
#
printf "\033c"
printf "\e[0;37m\n=====================================\n"
printf "\e[1;32mArduPlane Software In The Loop (SITL)\e[0;37m\n\n"
printf "Hugo Andrade <hugo.slip@gmail.com>\n"
printf "Version: $VERSION\n"
printf "=====================================\n\n"


# kill existing tasks
kill_tasks(){
  [ "$INSTANCE" -eq "0" ] && {
    if [ -n "$(ps ax|grep -i [a]rduplane.elf)" ]
    then
      kill -9 $(ps ax|grep -i [a]rduplane.elf|awk '{print $1}'|tr '\n' ' ')
    fi
    for pname in JSBSim mavproxy apm fgfs; do
  	   pkill "$pname"
    done
  }
  if [ -n "$(ps ax|grep -i [S]YSID_THISMAV=$INSTANCE)" ]; then
    kill -9 $(ps ax|grep -i [S]YSID_THISMAV=$INSTANCE|awk '{print $1}'|tr '\n' ' ')
  fi
}

check_mavproxy(){
mavproxy_version=$(mavproxy.py --version|grep Version|cut -d: -f 2|sed -e 's/^[ \t]*//')
if [ -z $mavproxy_version ]; then
  cat <<EOF
=========================================================
You need the latest MAVProxy version installed

Please get it from:

    https://github.com/Dronecode/MAVProxy.git

See more details in:

    http://dronecode.github.io/MAVProxy/html/index.html
=========================================================
EOF
       exit 1
else
       echo -e  "Mavproxy version .....: \e[1m$mavproxy_version \e[21m"
fi
}

check_git(){
git_version=$(git --version |cut -d ' ' -f 3)
if [ -z $git_version ]; then
  cat <<EOF
=====================================
Error, package git is not available

Get package:

    https://git-scm.com/download/
=====================================
EOF
       exit 1
else
       echo -e  "Git version ..........: \e[1m$git_version \e[21m"
fi
}

check_dependencies(){

if [ ! -d $ARDUPILOT_BASEDIR/.git ]; then
    cat <<EOF
============================================
Error, not a git repository: ardupilot

Please clone git from:

    git://github.com/ArduPilot/ardupilot.git
============================================
EOF
    exit 1
else
    echo -e  "Ardupilot folder git..: \e[1mok \e[21m"
fi

if [ ! -d $ARDUPILOT_BASEDIR/../jsbsim/.git ]; then
    cat <<EOF
=================================================================
Error, not a git repository: jsbsim

Please clone git from:

    git://github.com/tridge/jsbsim.git

See more details in:

    http://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
=================================================================
EOF
    exit 1
else
    echo -e  "JSBSim folder git.....: \e[1mok \e[21m"
fi
}

check_flightgear (){

if [ -z "$(which fgfs)" ]; then
  cat <<EOF
=========================================================
You need the latest FlightGear version installed

Please get it from:

    http://www.flightgear.org/download/

=========================================================
EOF
       exit 1
fi
}

trap kill_tasks SIGINT

check_git;
check_dependencies;
check_mavproxy;

cd $ARDUPILOT_BASEDIR/ArduPlane

###
# Rebuild ArduPlane.elf SITL
###
#
if [ $REBUILD == 1 ]; then
  pushd $ARDUPILOT_BASEDIR/ArduPlane
  make clean
  echo "Building ArduPlane Sitl"
  make sitl -j$NUM_PROCS || {
      make clean
      make sitl -j$NUM_PROCS || {
  	     echo >&2 "$0: Build failed"
  	     exit 1
      }
  }
  popd
fi

###
# Jsbsim / ArduPlane.elf, configuration and start
###
#
#

if [ -z "$DEFAULT_PARAMS" ]; then
  DEFAULT_PARAMS="$ARDUPILOT_BASEDIR/Tools/autotest/ArduPlane.parm"
fi

printf "\n\e[1mStart ArduPlane.elf SITL\e[21m\n\n"
printf "Start Location........: \e[1m$LOCATION\e[21m\n"
printf "Default Params........: \e[1m$DEFAULT_PARAMS\e[21m\n"
printf "ArduPlane Instance....: \e[1m$INSTANCE\e[21m\n"

cmd="-P SYSID_THISMAV=$((1+1*$INSTANCE))"

if [ $WIND == 1 ]; then
  WIND_DIR=$(($RANDOM%360))
  WIND_SPD=$((5+$RANDOM%10))
  cmd="$cmd -P SIM_WIND_DIR=$WIND_DIR"
  cmd="$cmd -P SIM_WIND_SPD=$WIND_SPD"
  printf "Wind Direction........: \e[1m$WIND_DIR\e[21m°\n"
  printf "Wind Speed............: \e[1m$WIND_SPD\e[21m m/s\n"
fi

if [ $VIBRATION == 1 ]; then
  ACC_NOISE=$((1+$RANDOM%4))
  cmd="$cmd -P SIM_ACC_RND=$ACC_NOISE"
  printf "Add Acceleration Noise: \e[1m$ACC_NOISE\e[21m m/s^2\n"
fi

if [ $WIPE_EEPROM == 1 ]; then
  printf "Wipe EEPROM...........: \e[1mok\e[21m\n"
  cmd="$cmd --wipe"
fi

# Run ArduPlane in background
$ARDUPILOT_BASEDIR/ArduPlane/ArduPlane.elf \
                            $cmd \
                            --speedup=1 \
                            -I$INSTANCE \
                            -S \
                            --home $LOCATION \
                            --model jsbsim \
                            --defaults $DEFAULT_PARAMS \
                            &>/dev/null &

###
# Mavproxy, configurantion and start
###
#
#
# setup ports for this instance
MASTER_PORT=$((5760+10*$INSTANCE))
SITL_PORT=$((5501+10*$INSTANCE))

mav_cmd=" --master tcp:127.0.0.1:$MASTER_PORT --sitl 127.0.0.1:$SITL_PORT"

if [ $MAVPROXY_ADDR_OUT1 != 0 ]; then
    mav_cmd="$mav_cmd --out $MAVPROXY_ADDR_OUT1"
fi

if [ $MAVPROXY_ADDR_OUT2 != 0 ]; then
    mav_cmd="$mav_cmd --out $MAVPROXY_ADDR_OUT2"
fi

mav_cmd="$mav_cmd --mission=$MISSION_NAME --aircraft=$AIRCRAFT_NAME"

if [ $MAVPROXY_CONSOLE == 1 ]; then
  mav_cmd="$mav_cmd --console"
fi

printf "\n\e[1mStart Mavproxy.py\e[21m\n\n"
printf "Aircraft Name.........: \e[1m$AIRCRAFT_NAME\e[21m\n"
printf "Mission Name..........: \e[1m$MISSION_NAME\e[21m\n"

if [ $MAVPROXY_ADDR_OUT1 != 0 ]; then
  printf "Output................: \e[1m$MAVPROXY_ADDR_OUT1\e[21m\n"
fi

if [ $MAVPROXY_ADDR_OUT2 != 0 ]; then
  printf "Output................: \e[1m$MAVPROXY_ADDR_OUT2\e[21m\n"
fi

printf "\n=====================================\n"
printf "\n\e[0;31mMavproxy shell:\e[0;37m\n\n"

###
# Start FlighGear Simulator
###
#
if [ $START_FG == 1 ] || [ $FG_MULT == 1 ]; then

  check_flightgear;
  cmd_mult=

  if [ $FG_MULT == 1 ]; then
    cmd_mult="--callsign=\"APMP-$((1+1*$INSTANCE))\""
    cmd_mult="$cmd_mult --multiplay=out,10,127.0.0.1,6000"
    cmd_mult="$cmd_mult --multiplay=in,10,127.0.0.1,$((6600+10*$INSTANCE))"
  fi

nice fgfs \
    $cmd_mult \
    --native-fdm=socket,in,10,,$((5503+10*$INSTANCE)),udp \
    --fdm=null \
    --aircraft=easystar \
    --fg-aircraft="$ARDUPILOT_BASEDIR/Tools/autotest/aircraft" \
    --airport=SBRJ \
    --geometry=650x550 \
    --bpp=32 \
    --timeofday=noon \
    --disable-sound \
    --disable-fullscreen \
    --disable-ai-models \
    --fog-disable \
    --wind=0@0 \
    $* &>/dev/null & \
    disown
fi

mavproxy.py $mav_cmd
