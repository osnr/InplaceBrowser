[ `uname` = Linux ] && export X=x86_64-apple-darwin11-
P=osx64 C="-arch x86_64" L="-arch x86_64 -install_name @rpath/libpng.dylib" \
	D=libpng.dylib A=libpng.a ./build.sh
