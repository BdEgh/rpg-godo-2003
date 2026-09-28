## RPGGodo2003

You can play YNFGs together with it! (i want cu so bad)

Download the tool for your windows/linux system from this link: https://github.com/BdEgh/rpg-godo-2003/releases

Turn on Multiplayer and set "Connect to" address to 
```ws://89.169.163.164:42424```

Change the other settings as you wish and you're ready to go!

----

## windows compilation

```powershell
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg; .\bootstrap-vcpkg.bat
$env:VCPKG_ROOT="vcpkg"
$env:PATH="$env:VCPKG_ROOT;$env:PATH"
vcpkg integrate install

add to User Settings (JSON):
    "cmake.configureSettings": {
        "CMAKE_TOOLCHAIN_FILE": "vcpkg/scripts/buildsystems/vcpkg.cmake"
    }

:: CMake VS path (add to env): C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin

:: debug:

& cmake -B build -S . `
  -DCMAKE_BUILD_TYPE=Debug `
  -DVCPKG_TARGET_TRIPLET="x64-windows-static" `
  -DCMAKE_TOOLCHAIN_FILE="vcpkg/scripts/buildsystems/vcpkg.cmake"

& cmake --build build --parallel --target easyrpg_godot --config Debug

:: release:

& cmake  -B build -S . `
  -DCMAKE_BUILD_TYPE=Release `
  -DVCPKG_TARGET_TRIPLET="x64-windows-static" `
  -DCMAKE_TOOLCHAIN_FILE="vcpkg/scripts/buildsystems/vcpkg.cmake"

& cmake --build build --parallel --target easyrpg_godot --config Release

:: stripped export example:

godot-4.6.2-stable>scons platform=windows target=template_release profile="C:\proj\demo\custom.py" build_profile="C:\proj\demo\stripped.gdbuild"
```

## linux compilation

```sh
git clone https://github.com/microsoft/vcpkg.git
./vcpkg/bootstrap-vcpkg.sh

mkdir build && cd build

cmake -S . -B build -D CMAKE_BUILD_TYPE=Release -D CMAKE_TOOLCHAIN_FILE=vcpkg/scripts/buildsystems/vcpkg.cmake

cmake -S . -B build -D CMAKE_BUILD_TYPE=Debug -D CMAKE_TOOLCHAIN_FILE=vcpkg/scripts/buildsystems/vcpkg.cmake

cmake --build build --parallel
```
---

<details>
<summary>cursed stuff</summary>

## android compilation

```bash
rm -rf build

export ANDROID_NDK_HOME=/home/bde/Android/Sdk/ndk/30.0.14904198

cmake -S . -B build \
  -G Ninja \
  -D CMAKE_BUILD_TYPE=Debug \
  -D CMAKE_TOOLCHAIN_FILE=vcpkg/scripts/buildsystems/vcpkg.cmake \
  -D VCPKG_CHAINLOAD_TOOLCHAIN_FILE=/home/bde/Android/Sdk/ndk/30.0.14904198/build/cmake/android.toolchain.cmake \
  -D VCPKG_TARGET_TRIPLET=arm64-android \
  -D ANDROID_ABI=arm64-v8a \
  -D ANDROID_PLATFORM=android-28 \
  -D CMAKE_MAKE_PROGRAM=/home/bde/Android/Sdk/cmake/4.1.2/bin/ninja

cmake --build build --parallel
```

## macos compilation (not using vcpkg, keeping it just for myself)

```bash
# install required binaries (list is not full, i forgor)
brew install pixman libpng zlib fmt cmake

# 2. configure & build
rm -rf build && \
  PKG_CONFIG_PATH="/opt/homebrew/opt/icu4c@78/lib/pkgconfig:/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH" \
  cmake -B build \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=/opt/homebrew/opt/llvm/bin/clang \
    -DCMAKE_CXX_COMPILER=/opt/homebrew/opt/llvm/bin/clang++ \
    -DPLAYER_TARGET_PLATFORM=godot \
    -DPLAYER_BUILD_LIBLCF=ON \
    -DPLAYER_ENABLE_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DICU_ROOT=/opt/homebrew/opt/icu4c@78 \
    -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/icu4c@78;/opt/homebrew/opt/llvm;/opt/homebrew" \
    -DCMAKE_IGNORE_PATH="/Library/Frameworks/Mono.framework/Headers;/Library/Frameworks/Mono.framework" && \
  cmake --build build --parallel
```

</details>
