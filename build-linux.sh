#!/bin/bash

# Deps infos
OPENSSL_VER="1.0.2n"
OPENSSL_URL="https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"
OPENSSL_SHA="370babb75f278c39e0c50e8c4e7493bc0f18db6867478341a832a982fd15a8fe"

DB_VER="6.1.29.NC"
DB_URL="http://download.oracle.com/berkeley-db/db-$DB_VER.tar.gz"
DB_SHA="e3404de2e111e95751107d30454f569be9ec97325d5ea302c95a058f345dfe0e"

BOOST_VER="1_53_0"
BOOST_URL="https://sourceforge.net/projects/boost/files/boost/${BOOST_VER//_/\.}/boost_$BOOST_VER.tar.gz"
BOOST_SHA="7c4d1515e0310e7f810cbbc19adb9b2d425f443cc7a00b4599742ee1bdfd4c39"

# Check root or user
if (( EUID == 0 )); then
	echo -e "\n- - - - - - - - - \n"
	echo "You are too root for this ! Recheck README.md file." 1>&2
	echo -e "\n- - - - - - - - - \n"
	exit
fi

# Check thread number. Keep n-1 thread(s) if nproc >= 2
nproc=$(nproc)
if [ $nproc -eq 1 ]
then
	((job=nproc))
elif [ $nproc -gt 1 ]
then
	((job=nproc-1))
fi
echo "Will use $job thread(s)"

# Pila home dir
echo "Creating ~/pila/ dir"
mkdir -p ~/pila/
PILA_ROOT=$HOME/pila/

# Remove build.log file
rm -f $PILA_ROOT/build.log

# Backup dir
mkdir -p $PILA_ROOT/backup/

# Check src dir & backup deps
ALL_DEPS=0
if [[ -d "$PILA_ROOT/src" ]]; then
	if [[ -d "$PILA_ROOT/src/deps/boost" && "$PILA_ROOT/src/deps/db" && "$PILA_ROOT/src/deps/openssl" ]]; then
		mv -f $PILA_ROOT/src/deps/ $PILA_ROOT/backup/
		echo "Deps backed up." | tee -a $PILA_ROOT/build.log
		ALL_DEPS=1
	elif [[ -d "$PILA_ROOT/backup/deps/boost" && "$PILA_ROOT/backup/deps/db" && "$PILA_ROOT/backup/deps/openssl" ]]; then
		echo "Deps already backed up." | tee -a $PILA_ROOT/build.log
		ALL_DEPS=1
	fi
else
	if [[ -d "$PILA_ROOT/backup/deps/boost" && "$PILA_ROOT/backup/deps/db" && "$PILA_ROOT/backup/deps/openssl" ]]; then
		echo "Deps already backed up." | tee -a $PILA_ROOT/build.log
		ALL_DEPS=1
	fi
fi

# Remove src dir
echo "Clean before clone" | tee -a $PILA_ROOT/build.log
rm -Rf $PILA_ROOT/src/

# Check existing pila binary
echo "Check existing binary" | tee -a $PILA_ROOT/build.log
if [[ -f "$PILA_ROOT/pilad" ]]; then
	BACKUP_PILAD="pilad-$(date +%s)"
	echo "Existing pilad binary ! Let's backup." | tee -a $PILA_ROOT/build.log
	mkdir -p $PILA_ROOT/backup/
	mv $PILA_ROOT/pilad $PILA_ROOT/backup/$BACKUP_PILAD
	rm -f pilad
fi

# Github
echo "Git clone pila in src dir" | tee -a $PILA_ROOT/build.log
cd $PILA_ROOT/
git clone https://github.com/openpila/pila.git src

# OpenSSL
function build_openssl {
	echo "OpenSSL Install" | tee -a $PILA_ROOT/build.log
	cd $PILA_ROOT
	rm -Rf $PILA_ROOT/src/deps/openssl/
	wget $OPENSSL_URL
	echo "$OPENSSL_SHA  openssl-$OPENSSL_VER.tar.gz" | sha256sum -c
	tar -xzf openssl-$OPENSSL_VER.tar.gz
	cd openssl-$OPENSSL_VER
	mkdir -p $PILA_ROOT/src/deps/openssl/
	./config threads no-comp --prefix=$PILA_ROOT/src/deps/openssl/
	make -j$job depend && make -j$job && make install && touch $PILA_ROOT/src/deps/openssl/current_openssl_$OPENSSL_VER
	# Clean
	cd $PILA_ROOT
	echo "Clean after OpenSSL install" | tee -a $PILA_ROOT/build.log
	rm -Rf openssl-$OPENSSL_VER/
	rm openssl-$OPENSSL_VER.tar.gz
}

# DB
function build_db {
	cd $PILA_ROOT
	rm -Rf $PILA_ROOT/src/deps/db/
	wget --no-check-certificate $DB_URL
	echo "$DB_SHA  db-$DB_VER.tar.gz" | sha256sum -c
	tar -xzf db-*.tar.gz
	echo "Compile & install Berkeley DB in deps folder" | tee -a $PILA_ROOT/build.log
	cd db-$DB_VER/build_unix/
	mkdir -p $PILA_ROOT/src/deps/db/
	../dist/configure --enable-cxx --disable-shared --prefix=$PILA_ROOT/src/deps/db/
	make -j$job && make install && touch $PILA_ROOT/src/deps/db/current_db_$DB_VER
	# Clean
	cd $PILA_ROOT
	echo "Clean after Berkeley DB install" | tee -a $PILA_ROOT/build.log
	rm -Rf db-$DB_VER/
	rm db-$DB_VER.tar.gz
}

# Boost
function build_boost {
	cd $PILA_ROOT
	rm -Rf $PILA_ROOT/src/deps/boost/
	wget $BOOST_URL
	echo "$BOOST_SHA  boost_$BOOST_VER.tar.gz" | sha256sum -c
	echo "Extract boost" | tee -a $PILA_ROOT/build.log
	tar -xzf boost_$BOOST_VER.tar.gz
	echo "mv boost to deps folder & rename" | tee -a $PILA_ROOT/build.log
	mv boost_$BOOST_VER src/deps/boost
	cd $PILA_ROOT/src/deps/boost/
	echo "Build boost system" | tee -a $PILA_ROOT/build.log
	./bootstrap.sh
	./bjam -j$job link=static toolset=gcc cxxflags=-std=gnu++0x --with-system release &
	touch $PILA_ROOT/src/deps/boost/current_boost_$BOOST_VER
	# Clean
	cd $PILA_ROOT
	echo "Clean after Boost install" | tee -a $PILA_ROOT/build.log
	rm boost_$BOOST_VER.tar.gz
}

if [[ $ALL_DEPS == 1 ]]; then
	mv $PILA_ROOT/backup/deps/boost/ $PILA_ROOT/src/deps/
	# Temp
	if ! [[ -f "$PILA_ROOT/src/deps/boost/current_boost_$BOOST_VER" ]]; then
		touch $PILA_ROOT/src/deps/boost/current_boost_$BOOST_VER
	fi
	mv $PILA_ROOT/backup/deps/db/ $PILA_ROOT/src/deps/
	mv $PILA_ROOT/backup/deps/openssl/ $PILA_ROOT/src/deps/
	rm -Rf $PILA_ROOT/backup/deps/
	echo "Deps restored." | tee -a $PILA_ROOT/build.log
else
	build_openssl
	build_db
	build_boost
fi

# Deps upgrade ?
if ! [[ -f "$PILA_ROOT/src/deps/openssl/current_openssl_$OPENSSL_VER" ]]; then
	build_openssl
fi
if ! [[ -f "$PILA_ROOT/src/deps/db/current_db_$DB_VER" ]]; then
	build_db
fi
if ! [[ -f "$PILA_ROOT/src/deps/boost/current_boost_$BOOST_VER" ]]; then
	build_boost
fi

# Pila daemon
echo "pilad bjam build" | tee -a $PILA_ROOT/build.log
cd $PILA_ROOT/src/coin/test/
../../deps/boost/bjam -j$job toolset=gcc cxxflags=-std=gnu++0x hardcode-dll-paths=false release | tee -a $PILA_ROOT/build.log
cd $PILA_ROOT/src/coin/test/bin/gcc-*/release/link-static/
STACK_OUT=$(pwd)
if [[ -f "$STACK_OUT/stack" ]]; then
	echo "pilad built !" | tee -a $PILA_ROOT/build.log
	strip $STACK_OUT/stack
	cp $STACK_OUT/stack $PILA_ROOT/pilad
	# Check if pilad is running
	RESTART=0
	pgrep -l pilad && RESTART=1
else
	cd $PILA_ROOT/src/coin/test/
	echo "pilad building error..." 
	exit
fi

# Start or restart
cd $PILA_ROOT

if [[ $RESTART == 1 ]]; then
	echo -e "\n- - - - - - - - - \n"
	echo " ! Previous Pila daemon is still running !"
	echo -e "\n- - - - - - - - - \n"
	echo " Please kill the process & start the fresh pilad with:"
	echo " cd ~/pila/ && screen -d -S pilad -m ./pilad"
	echo -e "\n- - - - - - - - - \n"
else
	screen -d -S pilad -m ./pilad
	echo -e "\n- - - - - - - - - \n"
	echo " Pila daemon launched in a screen session. To switch:"
	echo -e "\n- - - - - - - - - \n"
	echo " screen -x pilad"
	echo " Ctrl-a Ctrl-d to detach without kill the daemon"
	echo -e "\n- - - - - - - - - \n"
fi
