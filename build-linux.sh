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

# Vcash home dir
echo "Creating ~/pila/ dir"
mkdir -p ~/pila/
VCASH_ROOT=$HOME/pila/

# Remove build.log file
rm -f $VCASH_ROOT/build.log

# Backup dir
mkdir -p $VCASH_ROOT/backup/

# Check src dir & backup deps
ALL_DEPS=0
if [[ -d "$VCASH_ROOT/src" ]]; then
	if [[ -d "$VCASH_ROOT/src/deps/boost" && "$VCASH_ROOT/src/deps/db" && "$VCASH_ROOT/src/deps/openssl" ]]; then
		mv -f $VCASH_ROOT/src/deps/ $VCASH_ROOT/backup/
		echo "Deps backed up." | tee -a $VCASH_ROOT/build.log
		ALL_DEPS=1
	elif [[ -d "$VCASH_ROOT/backup/deps/boost" && "$VCASH_ROOT/backup/deps/db" && "$VCASH_ROOT/backup/deps/openssl" ]]; then
		echo "Deps already backed up." | tee -a $VCASH_ROOT/build.log
		ALL_DEPS=1
	fi
else
	if [[ -d "$VCASH_ROOT/backup/deps/boost" && "$VCASH_ROOT/backup/deps/db" && "$VCASH_ROOT/backup/deps/openssl" ]]; then
		echo "Deps already backed up." | tee -a $VCASH_ROOT/build.log
		ALL_DEPS=1
	fi
fi

# Remove src dir
echo "Clean before clone" | tee -a $VCASH_ROOT/build.log
rm -Rf $VCASH_ROOT/src/

# Check existing pila binary
echo "Check existing binary" | tee -a $VCASH_ROOT/build.log
if [[ -f "$VCASH_ROOT/pilad" ]]; then
	BACKUP_VCASHD="pilad-$(date +%s)"
	echo "Existing pilad binary ! Let's backup." | tee -a $VCASH_ROOT/build.log
	mkdir -p $VCASH_ROOT/backup/
	mv $VCASH_ROOT/pilad $VCASH_ROOT/backup/$BACKUP_VCASHD
	rm -f pilad
fi

# Github
echo "Git clone pila in src dir" | tee -a $VCASH_ROOT/build.log
cd $VCASH_ROOT/
git clone https://github.com/openpila/pila.git src

# OpenSSL
function build_openssl {
	echo "OpenSSL Install" | tee -a $VCASH_ROOT/build.log
	cd $VCASH_ROOT
	rm -Rf $VCASH_ROOT/src/deps/openssl/
	wget $OPENSSL_URL
	echo "$OPENSSL_SHA  openssl-$OPENSSL_VER.tar.gz" | sha256sum -c
	tar -xzf openssl-$OPENSSL_VER.tar.gz
	cd openssl-$OPENSSL_VER
	mkdir -p $VCASH_ROOT/src/deps/openssl/
	./config threads no-comp --prefix=$VCASH_ROOT/src/deps/openssl/
	make -j$job depend && make -j$job && make install && touch $VCASH_ROOT/src/deps/openssl/current_openssl_$OPENSSL_VER
	# Clean
	cd $VCASH_ROOT
	echo "Clean after OpenSSL install" | tee -a $VCASH_ROOT/build.log
	rm -Rf openssl-$OPENSSL_VER/
	rm openssl-$OPENSSL_VER.tar.gz
}

# DB
function build_db {
	cd $VCASH_ROOT
	rm -Rf $VCASH_ROOT/src/deps/db/
	wget --no-check-certificate $DB_URL
	echo "$DB_SHA  db-$DB_VER.tar.gz" | sha256sum -c
	tar -xzf db-*.tar.gz
	echo "Compile & install Berkeley DB in deps folder" | tee -a $VCASH_ROOT/build.log
	cd db-$DB_VER/build_unix/
	mkdir -p $VCASH_ROOT/src/deps/db/
	../dist/configure --enable-cxx --disable-shared --prefix=$VCASH_ROOT/src/deps/db/
	make -j$job && make install && touch $VCASH_ROOT/src/deps/db/current_db_$DB_VER
	# Clean
	cd $VCASH_ROOT
	echo "Clean after Berkeley DB install" | tee -a $VCASH_ROOT/build.log
	rm -Rf db-$DB_VER/
	rm db-$DB_VER.tar.gz
}

# Boost
function build_boost {
	cd $VCASH_ROOT
	rm -Rf $VCASH_ROOT/src/deps/boost/
	wget $BOOST_URL
	echo "$BOOST_SHA  boost_$BOOST_VER.tar.gz" | sha256sum -c
	echo "Extract boost" | tee -a $VCASH_ROOT/build.log
	tar -xzf boost_$BOOST_VER.tar.gz
	echo "mv boost to deps folder & rename" | tee -a $VCASH_ROOT/build.log
	mv boost_$BOOST_VER src/deps/boost
	cd $VCASH_ROOT/src/deps/boost/
	echo "Build boost system" | tee -a $VCASH_ROOT/build.log
	./bootstrap.sh
	./bjam -j$job link=static toolset=gcc cxxflags=-std=gnu++0x --with-system release &
	touch $VCASH_ROOT/src/deps/boost/current_boost_$BOOST_VER
	# Clean
	cd $VCASH_ROOT
	echo "Clean after Boost install" | tee -a $VCASH_ROOT/build.log
	rm boost_$BOOST_VER.tar.gz
}

if [[ $ALL_DEPS == 1 ]]; then
	mv $VCASH_ROOT/backup/deps/boost/ $VCASH_ROOT/src/deps/
	# Temp
	if ! [[ -f "$VCASH_ROOT/src/deps/boost/current_boost_$BOOST_VER" ]]; then
		touch $VCASH_ROOT/src/deps/boost/current_boost_$BOOST_VER
	fi
	mv $VCASH_ROOT/backup/deps/db/ $VCASH_ROOT/src/deps/
	mv $VCASH_ROOT/backup/deps/openssl/ $VCASH_ROOT/src/deps/
	rm -Rf $VCASH_ROOT/backup/deps/
	echo "Deps restored." | tee -a $VCASH_ROOT/build.log
else
	build_openssl
	build_db
	build_boost
fi

# Deps upgrade ?
if ! [[ -f "$VCASH_ROOT/src/deps/openssl/current_openssl_$OPENSSL_VER" ]]; then
	build_openssl
fi
if ! [[ -f "$VCASH_ROOT/src/deps/db/current_db_$DB_VER" ]]; then
	build_db
fi
if ! [[ -f "$VCASH_ROOT/src/deps/boost/current_boost_$BOOST_VER" ]]; then
	build_boost
fi

# Vcash daemon
echo "pilad bjam build" | tee -a $VCASH_ROOT/build.log
cd $VCASH_ROOT/src/coin/test/
../../deps/boost/bjam -j$job toolset=gcc cxxflags=-std=gnu++0x hardcode-dll-paths=false release | tee -a $VCASH_ROOT/build.log
cd $VCASH_ROOT/src/coin/test/bin/gcc-*/release/link-static/
STACK_OUT=$(pwd)
if [[ -f "$STACK_OUT/stack" ]]; then
	echo "pilad built !" | tee -a $VCASH_ROOT/build.log
	strip $STACK_OUT/stack
	cp $STACK_OUT/stack $VCASH_ROOT/pilad
	# Check if pilad is running
	RESTART=0
	pgrep -l pilad && RESTART=1
else
	cd $VCASH_ROOT/src/coin/test/
	echo "pilad building error..." 
	exit
fi

# Start or restart
cd $VCASH_ROOT

if [[ $RESTART == 1 ]]; then
	echo -e "\n- - - - - - - - - \n"
	echo " ! Previous Vcash daemon is still running !"
	echo -e "\n- - - - - - - - - \n"
	echo " Please kill the process & start the fresh pilad with:"
	echo " cd ~/pila/ && screen -d -S pilad -m ./pilad"
	echo -e "\n- - - - - - - - - \n"
else
	screen -d -S pilad -m ./pilad
	echo -e "\n- - - - - - - - - \n"
	echo " Vcash daemon launched in a screen session. To switch:"
	echo -e "\n- - - - - - - - - \n"
	echo " screen -x pilad"
	echo " Ctrl-a Ctrl-d to detach without kill the daemon"
	echo -e "\n- - - - - - - - - \n"
fi
