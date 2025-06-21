#!/bin/bash
#set -e  

# Clean previous build outputs
rm -rf out/ AGNI-*

# AOSP Clang
CLANG_VERSION="clang-r547379"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/${CLANG_VERSION}.tgz"
ARCHIVE_NAME="aosp-clang.tar.gz"

# Set the working directory and paths
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
ZIMAGE_DIR="$(pwd)/out/arch/arm64/boot"
KERNEL_DEFCONFIG=vendor/munch_defconfig
restore=0

# Set environment variables for the build
export PATH="${MAIN}/clang/bin:${MAIN}/clang/gcc/bin:${MAIN}/clang/gcc32/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64

LINKER="ld.lld"
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
TIME="$(date "+%Y%m%d-%H%M%S")"

# Colors for terminal output
blue='\033[0;34m'
nocol='\033[0m'

# Check or Download AOSP Clang if it doesn't exist
if [ ! -d "$MAIN/clang" ]; then
    echo "No clang compiler found ... Downloading AOSP Clang"

    # Download Clang archive
    if ! wget -P "$MAIN" "$CLANG_URL" -O "$MAIN/$ARCHIVE_NAME"; then
        echo "Failed to download. Exiting..."
        exit 1
    fi

    # Create clang directory and extract archive
    mkdir -p "$MAIN/clang"

    if ! tar -xvf "$MAIN/$ARCHIVE_NAME" -C "$MAIN/clang"; then
        echo "Failed to extract Clang. Exiting..."
        exit 1
    fi

    # Clean up the archive file
    rm -rf "$MAIN/$ARCHIVE_NAME"

    # Clone GCC for aarch64 (64-bit) and arm (32-bit)
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 "$MAIN/clang/gcc" || { echo "Failed to clone GCC for aarch64. Exiting..."; exit 1; }
    git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git --depth=1 "$MAIN/clang/gcc32" || { echo "Failed to clone GCC for arm. Exiting..."; exit 1; }

    # Verify GCC toolchains were cloned
    if [ ! -d "$MAIN/clang/gcc" ] || [ ! -d "$MAIN/clang/gcc32" ]; then
        echo "Failed :( Exiting..."
        exit 1
    fi
fi

clear

# Display initialization message
echo -e "$blue***********************************************"
echo "          Initializing Kernel Compilation          "
echo -e "***********************************************$nocol"

# Prompt user to choose the build type (MIUI or AOSP)
echo "Choose the build type:"
echo "1. MIUI"
echo "2. AOSP"
read -p "Enter the number of your choice: " build_choice

# Modify dtsi file if MIUI build is selected
if [ "$build_choice" = "1" ]; then
    # Make adjustments for MIUI build
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <70>;$/qcom,mdss-pan-physical-width-dimension = <695>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <155>;$/qcom,mdss-pan-physical-height-dimension = <1546>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    zip_name="MIUI"
    restore=1
elif [ "$build_choice" = "2" ]; then
    echo "AOSP build selected. No modifications needed."
    zip_name="AOSP"
else
    echo "Invalid choice. Exiting..."
    exit 1
fi

# Start the kernel build process
make $KERNEL_DEFCONFIG O=out CC=clang ARCH=arm64
make -j$(nproc --all) O=out \
                      CC=clang \
                      ARCH=arm64 \
                      SUBARCH=arm64 \
                      LD=ld.lld \
                      LLVM=1 \
	                  LLVM_IAS=1 \
                      CLANG_TRIPLE=aarch64-linux-gnu- \
	                  CROSS_COMPILE=aarch64-linux-android- \
	                  CROSS_COMPILE_COMPAT=arm-linux-androideabi-
                     
# Create a zip file with the built kernel
mkdir -p tmp
cp -fp $ZIMAGE_DIR/Image.gz tmp
cp -fp $ZIMAGE_DIR/dtbo.img tmp
cp -fp $ZIMAGE_DIR/dtb.img tmp
cp -rp ./anykernel/* tmp

cd tmp
mv dtb.img dtb
7za a -mx9 tmp.zip *
cd ..

# Clean up temporary files and rename the zip
rm -f *.zip
cp -fp tmp/tmp.zip AGNI-Munch-${zip_name}-$TIME.zip
rm -rf tmp

# Function to revert changes made to the dtsi file
revert_changes() {
    echo "Reverting changes made to the dtsi file..."
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <695>;$/qcom,mdss-pan-physical-width-dimension = <70>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <1546>;$/qcom,mdss-pan-physical-height-dimension = <155>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
}

# Revert changes after compiling kernel
if [ $restore == 1 ]; then
    revert_changes
fi