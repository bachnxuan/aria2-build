#!/usr/bin/env bash
# Aria2 static binary build script
# Inspired from abcfy2/aria2-static-build
# by @bachnxuan

set -euox pipefail

DEPS=/tmp/aria2-deps
PREFIX=$(pwd)/build_libs

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
  build-essential curl wget jq unzip xz-utils git autoconf automake libtool \
  pkg-config ca-certificates gettext

mkdir -p "$DEPS" "$PREFIX"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CC="ccache gcc"
export CXX="ccache g++"
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -static"
export CFLAGS="-O2 -pipe -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"

download() { wget -q --show-progress -c --timeout=10 --tries=3 --retry-connrefused "$@"; }

setup_cmake() {
  tag=$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest | jq -r .tag_name | sed 's/^v//')
  url="https://github.com/Kitware/CMake/releases/download/v${tag}/cmake-${tag}-linux-x86_64.tar.gz"
  download -O /tmp/cmake.tgz "$url"
  sudo tar -xzf /tmp/cmake.tgz -C /usr/local --strip-components=1
}

setup_ninja() {
  tag=$(curl -fsSL https://api.github.com/repos/ninja-build/ninja/releases/latest | jq -r .tag_name)
  url="https://github.com/ninja-build/ninja/releases/download/${tag}/ninja-linux.zip"
  download -O /tmp/ninja.zip "$url"
  sudo unzip -qo /tmp/ninja.zip -d /usr/local/bin
}

setup_zlib_ng() {
  tag=$(curl -fsSL https://api.github.com/repos/zlib-ng/zlib-ng/releases | jq -r '.[0].tag_name')
  url="https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${tag}.tar.gz"
  download -O "$DEPS/zlib-ng.tgz" "$url"
  rm -rf "$DEPS/zlib-ng" && mkdir "$DEPS/zlib-ng"
  tar -xzf "$DEPS/zlib-ng.tgz" --strip-components=1 -C "$DEPS/zlib-ng"
  cd "$DEPS/zlib-ng"
  cmake -B build -G Ninja -DBUILD_SHARED_LIBS=OFF -DZLIB_COMPAT=ON -DCMAKE_INSTALL_PREFIX="$PREFIX" -DWITH_GTEST=OFF
  cmake --build build && cmake --install build
  cd -
}

setup_openssl() {
  file=$(curl -fsSL https://www.openssl.org/source/ | grep -oE 'openssl-3[0-9.]*[a-z]?\.tar\.gz' | sort -V | tail -1)
  url="https://www.openssl.org/source/${file}"
  download -O "$DEPS/openssl.tgz" "$url"
  rm -rf "$DEPS/openssl" && mkdir "$DEPS/openssl"
  tar -xzf "$DEPS/openssl.tgz" --strip-components=1 -C "$DEPS/openssl"
  cd "$DEPS/openssl"
  ./Configure no-shared --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
  make -j"$(nproc)" && make install_sw
  cd -
}

setup_libiconv() {
  ver=$(curl -fsSL https://ftpmirror.gnu.org/libiconv/ \
        | grep -oE 'libiconv-[0-9.]+\.tar\.gz' \
        | sort -Vr | head -1 \
        | sed 's/libiconv-\(.*\)\.tar\.gz/\1/')
  url="https://ftpmirror.gnu.org/libiconv/libiconv-${ver}.tar.gz"
  download -O "$DEPS/libiconv.tgz" "$url"
  rm -rf "$DEPS/libiconv" && mkdir "$DEPS/libiconv"
  tar -xzf "$DEPS/libiconv.tgz" --strip-components=1 -C "$DEPS/libiconv"
  cd "$DEPS/libiconv"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static
  make -j"$(nproc)" && make install
  cd -
}

setup_libxml2() {
  tag=$(curl -fsSL https://api.github.com/repos/GNOME/libxml2/tags | jq -r '.[0].name')
  url="https://gitlab.gnome.org/GNOME/libxml2/-/archive/${tag}/libxml2-${tag}.tar.gz"
  download -O "$DEPS/libxml2.tgz" "$url"
  rm -rf "$DEPS/libxml2" && mkdir "$DEPS/libxml2"
  tar -xzf "$DEPS/libxml2.tgz" --strip-components=1 -C "$DEPS/libxml2"
  cd "$DEPS/libxml2"
  autoreconf -i
  ./configure --prefix="$PREFIX" --without-python --without-icu --disable-shared --enable-static
  make -j"$(nproc)" && make install
  cd -
}

setup_c_ares() {
  tag=$(curl -fsSL https://api.github.com/repos/c-ares/c-ares/releases | jq -r '.[0].tag_name')
  ver=${tag#v}
  url="https://github.com/c-ares/c-ares/releases/download/${tag}/c-ares-${ver}.tar.gz"
  download -O "$DEPS/c-ares.tgz" "$url"
  rm -rf "$DEPS/c-ares" && mkdir "$DEPS/c-ares"
  tar -xzf "$DEPS/c-ares.tgz" --strip-components=1 -C "$DEPS/c-ares"
  cd "$DEPS/c-ares"
  autoreconf -fi
  ./configure --prefix="$PREFIX" --disable-shared --enable-static
  make -j"$(nproc)" && make install
  cd -
}

setup_libssh2() {
  tag=$(curl -fsSL https://api.github.com/repos/libssh2/libssh2/releases/latest \
          | jq -r .tag_name)
  ver=${tag#libssh2-}
  url="https://github.com/libssh2/libssh2/releases/download/${tag}/libssh2-${ver}.tar.gz"
  download -O "$DEPS/libssh2.tgz" "$url"
  rm -rf "$DEPS/libssh2" && mkdir "$DEPS/libssh2"
  tar -xzf "$DEPS/libssh2.tgz" --strip-components=1 -C "$DEPS/libssh2"
  cd "$DEPS/libssh2"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static
  make -j"$(nproc)" && make install
  cd -
}

setup_sqlite() {
  tag=$(curl -fsSL https://api.github.com/repos/sqlite/sqlite/tags |
    jq -r '.[0].name')
  url="https://github.com/sqlite/sqlite/archive/refs/tags/${tag}.tar.gz"
  download -O "$DEPS/sqlite.tgz" "$url"

  rm -rf "$DEPS/sqlite" && mkdir "$DEPS/sqlite"
  tar -xzf "$DEPS/sqlite.tgz" --strip-components=1 -C "$DEPS/sqlite"
  cd "$DEPS/sqlite"
  ./configure --prefix="$PREFIX" --enable-static --disable-shared --disable-load-extension
  make -j"$(nproc)"
  make install
  cd -
}

build_aria2() {
  tag=$(curl -fsSL https://api.github.com/repos/aria2/aria2/releases/latest | jq -r .tag_name)
  ver=${tag#release-}
  url="https://github.com/aria2/aria2/releases/download/${tag}/aria2-${ver}.tar.gz"
  download -O "$DEPS/aria2.tgz" "$url"
  rm -rf "$DEPS/aria2" && mkdir "$DEPS/aria2"
  tar -xzf "$DEPS/aria2.tgz" --strip-components=1 -C "$DEPS/aria2"
  cd "$DEPS/aria2"
  CFLAGS="$CFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS -s -Wl,--gc-sections" \
    ./configure ARIA2_STATIC=yes --prefix="$PREFIX" \
    --enable-static --disable-shared --enable-silent-rules \
    --with-openssl --with-libxml2 --with-libssh2 \
    --with-libcares --with-zlib --with-sqlite3 \
    --without-gnutls --without-libnettle --without-libgmp
  make -j"$(nproc)"
  strip --strip-all src/aria2c
  cp src/aria2c "$OLDPWD/aria2c"
  cd -
}

command -v cmake  >/dev/null || setup_cmake
command -v ninja  >/dev/null || setup_ninja
setup_zlib_ng
setup_openssl
setup_libiconv
setup_libxml2
setup_c_ares
setup_libssh2
setup_sqlite
build_aria2

echo "aria2c built successfully"
