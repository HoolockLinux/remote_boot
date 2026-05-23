#!/usr/bin/env bash
# For bash 3.2+

set -e;
OS="$(uname -s)"

SCRIPT_PATH="$(cd $(dirname -- "${BASH_SOURCE[0]}"); pwd -P)"

check_cmd()
{
	if [ "$(command -v "$1")" = "" ]; then
		echo "[-] $1 not found!";
		if [ "$2" != "" ]; then
			echo "[-] $1 project URL: $2";
		fi
		exit 1;
	fi
}

err_handler()
{
	[ $? -eq 0 ] && exit
	echo "[-] An error occured";
	exit 1;
}

root_check()
{
	# Allow build as non-root
	if [ "$OS" != "Darwin" ] && [ "$(id -u)" != "0" ] && ([ "$1" = "prep" ] || [ "$1" = "boot" ]); then
		echo "[-] Please run as root";
		exit 1;
	fi
}

make_check()
{
	if [ "$(command -v gmake)" != "" ]; then
		make_check_MAKE=gmake
	else
		make_check_MAKE=make
	fi

	if [ "$(command -v $make_check_MAKE)" = "" ] || ! ("$make_check_MAKE" --version | grep -q "GNU Make"); then
		echo "[-] GNU Make not found!";
		exit 1
	fi

	if "$make_check_MAKE" --version | grep -q "2006  Free Software Foundation, Inc"; then
		echo "[-] Your GNU Make version is from 2006 and too outdated";
		echo "[-] Please update to some remotely recent version of GNU Make"
		exit 1
	fi

	printf "$make_check_MAKE"
}

vendor_check()
{
	if ! [ -f "${SCRIPT_PATH}/vendor/$1/Makefile" ]; then
		echo "[-] Submodule $1 missing";
		echo "[-] Maybe try: git submodule update --init --recursive";
		exit 1;
	fi
}

gaster_build()
{
	if ! [ -f "$GASTER" ]; then
		if [ "$OS" = "Darwin" ]; then
			"$MAKE" -C "${SCRIPT_PATH}/vendor/gaster" macos
		else
			"$MAKE" -C "${SCRIPT_PATH}/vendor/gaster" libusb_dyn
		fi
	fi
}

hBootPatcher_build()
{
	if ! [ -f "$HBOOTPATCHER" ]; then
		"$MAKE" -C "${SCRIPT_PATH}/vendor/hBootPatcher"
	fi
}

hKernelFWExtractor_build()
{
	if ! [ -f "$HKERNELFWEXTRACTOR" ]; then
		"$MAKE" -C "${SCRIPT_PATH}/vendor/hKernelFWExtractor"
	fi
}

usb_check()
{
	if [ "$OS" != "Darwin" ]; then
		check_cmd "lsusb"
	fi

}

update_submodules()
{
	if [ -f "${SCRIPT_PATH}/.git" ]; then
		if [ "$(git submodule update --init --recursive)" != "" ]; then
			rm -f "$GASTER" "$HBOOTPATCHER";
		fi
	fi
}

usage_check()
{
	if [ "$1" != "prep" ] && [ "$1" != "boot" ] && [ "$1" != "firmware" ] || ([ "$1" = "boot" ] && ([ "$2" = "" ] || [ "$3" = "" ]);); then
		if [ "$1" = "build" ]; then
			exit 0;
		fi

		printf "Usage: \t$0\n\tprep\t\t\t\t\t\tfor preparing bootchain files\n";
		printf "\tboot <m1n1-idevice.macho> <monitor-stub.macho>\tBoot m1n1\n";
		printf "\tfirmware\t\tGather firmware"

		if [ "$1" = "help" ]; then
			exit 0;
		else
			exit 1;
		fi
	fi
}

dfu_poll()
{
	echo "[*] Waiting for device in DFU mode"

	if [ "$OS" = "Darwin" ]; then
		while ! system_profiler SPUSBDataType SPUSBHostDataType | grep -qF ' Apple Mobile Device (DFU Mode)'; do
			sleep 1;
		done
	else
		while ! lsusb 2> /dev/null | grep -qF '05ac:1227'; do
			sleep 1;
		done
	fi
}

gaster_pwn()
{
	echo "[*] Detected device"

	"$GASTER" pwn
	"$GASTER" decrypt_kbag 000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 > /dev/null || true
}

get_device_info()
{
	CPID="$(irecovery -q | grep CPID | sed -E 's/^CPID: (.*)$/\1/')"
	MODEL="$(irecovery -q | grep MODEL | sed -E 's/^MODEL: (.*)$/\1/')"
	PRODUCT="$(irecovery -q | grep PRODUCT | sed -E 's/^PRODUCT: (.*)$/\1/')"

	if [ "$CPID" = "0x8960" ] || [ "$CPID" = "0x7000" ] ||[ "$CPID" = "0x7001" ] || [ "$CPID" = "0x8000" ] || [ "$CPID" = "0x8001" ] || [ "$CPID" = "0x8003" ]; then
		two_stage="1";
	else
		two_stage="0";
	fi
}

prepare_boot_files()
{
	ipsw_dl_args=""

	if [ "$CPID" = "0x8012" ]; then
		ipsw_dl_args="download ipsw --ibridge -d $PRODUCT -m $MODEL --version 7.4"
	elif [ "$PRODUCT" = "AudioAccessory1,1" ]; then
		# 16.4
		ipsw_dl_args="download appledb --type ota --os audioOS -d "$PRODUCT" --build 20L497 --release -fy"
		fw_prefix="AssetData/boot/"
	elif [ "$PRODUCT" = "AppleTV5,3" ] || [ "$PRODUCT" = "AppleTV6,2" ]; then
		# 16.4
		ipsw_dl_args="download appledb --type ota --os tvOS -d "$PRODUCT" --build 20L497 --release -fy"
		fw_prefix="AssetData/boot/"
	fi

	if [ "$ipsw_dl_args" = "" ]; then
		LATEST_MAJOR="$(ipsw download ipsw -m "$MODEL" -d "$PRODUCT" --show-latest-version | cut -d. -f1)"

		if [ "$LATEST_MAJOR" -ge "16" ]; then
			ipsw_dl_args="download ipsw --version 16.4 -m $MODEL -d $PRODUCT -fy";
		elif [ "$LATEST_MAJOR" -ge "15" ]; then
			ipsw_dl_args="download ipsw --version 15.1 -m $MODEL -d $PRODUCT -fy";
		elif [ "$LATEST_MAJOR" -ge "12" ]; then
			ipsw_dl_args="download ipsw --version 12.4 -m $MODEL -d $PRODUCT -fy";
		else
			echo "[-] Unsupported latest major $LATEST_MAJOR";
		fi
	fi

	pushd "$WORK";
	ipsw ${ipsw_dl_args} --pattern "^${fw_prefix}BuildManifest.plist"'$'
	manifest="$(find "$(pwd)" -name BuildManifest.plist -type f)"

	IBSS_PATTERN="$(awk "/""$MODEL""/{x=1}x&&/iBSS[.]/{print;exit}" $manifest | sed -E 's/<string>(.*)<\/string>/\1/' | tr -d '\t')"
	ipsw ${ipsw_dl_args} --pattern "^${fw_prefix}${IBSS_PATTERN}"'$'
	IBSS_PATH="$(find "$(pwd)" -name "$(basename $IBSS_PATTERN)" -type f)"

	if [ "$two_stage" = "1" ]; then
		IBEC_PATTERN="$(awk "/""$MODEL""/{x=1}x&&/iBEC[.]/{print;exit}" $manifest | sed -E 's/<string>(.*)<\/string>/\1/' | tr -d '\t')"
		ipsw ${ipsw_dl_args} --pattern "^${fw_prefix}${IBEC_PATTERN}"'$'
		IBEC_PATH="$(find "$(pwd)" -name "$(basename $IBEC_PATTERN)" -type f)"
	fi

	DTRE_PATTERN="$(awk "/""$MODEL""/{x=1}x&&/DeviceTree[.]/{print;exit}" $manifest | sed -E 's/<string>(.*)<\/string>/\1/' | tr -d '\t')"
	ipsw ${ipsw_dl_args} --pattern "^${fw_prefix}${DTRE_PATTERN}"'$'
	DTRE_PATH="$(find "$(pwd)" -name "$(basename $DTRE_PATTERN)" -type f)"

	"$GASTER" decrypt "$IBSS_PATH" "$WORK/iBSS_${MODEL}_${PRODUCT}.bin"

	if [ "$two_stage" = "1" ]; then
		"$GASTER" decrypt "$IBEC_PATH" "$WORK/iBEC_${MODEL}_${PRODUCT}.bin"
	fi

	ipsw img4 im4p extract -o "$WORK/DeviceTree_${MODEL}_${PRODUCT}.bin" "$DTRE_PATH"

	"$HBOOTPATCHER" -airs "$WORK/iBSS_${MODEL}_${PRODUCT}.bin" "$WORK/iBSS_${MODEL}_${PRODUCT}_patched.bin";

	if [ "$two_stage" = "1" ]; then
		"$HBOOTPATCHER" -airs "$WORK/iBEC_${MODEL}_${PRODUCT}.bin" "$WORK/iBEC_${MODEL}_${PRODUCT}_patched.bin";
	fi

	popd

	ipsw img4 create --input "$WORK/iBSS_${MODEL}_${PRODUCT}_patched.bin" --type ibss --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/iBSS_${MODEL}_${PRODUCT}.img4"

	if [ "$two_stage" = "1" ]; then
		ipsw img4 create --input "$WORK/iBEC_${MODEL}_${PRODUCT}_patched.bin" --type ibec --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/iBEC_${MODEL}_${PRODUCT}.img4"
	fi
	ipsw img4 create --input "$WORK/DeviceTree_${MODEL}_${PRODUCT}.bin" --type rdtr --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/RestoreDeviceTree_${MODEL}_${PRODUCT}.img4"
}

boot_device()
{
	if ! [ -f "$SCRIPT_PATH/cache/RestoreDeviceTree_${MODEL}_${PRODUCT}.img4" ]; then
		rm -rf "$WORK";
		echo "[-] Prepare boot files first!"
		exit 1;
	fi

	ipsw img4 create --input "$SCRIPT_PATH/empty_trustcache.bin" --type rtsc --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${WORK}/RestoreTrustCache_${MODEL}_${PRODUCT}.img4"

	if [ "$two_stage" = "1" ]; then
		ipsw img4 create --input "$2" --type rkrn --extra "$3" --compress lzss --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${WORK}/RestoreKernelCache_${MODEL}_${PRODUCT}.img4"
	else
		ipsw img4 create --input "$2" --type rkrn --compress none --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${WORK}/RestoreKernelCache_${MODEL}_${PRODUCT}.img4"
	fi

	"$GASTER" reset
	sleep 1;

	irecovery -f "${SCRIPT_PATH}/cache/iBSS_${MODEL}_${PRODUCT}.img4"

	echo "[*] Sent iBSS. A cable replug may be required on some setups."

	sleep 2;

	if [ "$two_stage" = "1" ]; then
		irecovery -f "${SCRIPT_PATH}/cache/iBEC_${MODEL}_${PRODUCT}.img4"
		echo "[*] Sent iBEC. A cable replug may be required on some setups."

		sleep 2;
	fi

	irecovery -f "${SCRIPT_PATH}/cache/RestoreDeviceTree_${MODEL}_${PRODUCT}.img4"
	irecovery -c devicetree
	irecovery -f "${WORK}/RestoreTrustCache_${MODEL}_${PRODUCT}.img4"
	irecovery -c firmware
	irecovery -f "${WORK}/RestoreKernelCache_${MODEL}_${PRODUCT}.img4"
	irecovery -c bootx

	echo "[*] Booted device";
}

get_firmware()
{
	if [ "$1" != "firmware" ]; then
		return
	fi

	WORK="$(mktemp -d)";
	mkdir -p "${SCRIPT_PATH}/firmware"
	mkdir "$WORK/kernels"
	pushd "$WORK/kernels"
	ipsw download ipsw --build 20E247 -d iPhone10,3 --kernel
	ipsw download appledb --type ota --os tvOS -d AppleTV6,2 --build 20L497 --kernel --release -fy
	ipsw download ipsw --build 20E246 -d iPad7,1 --kernel
	ipsw download ipsw --build 20E246 -d iPad7,11 --kernel
	ipsw download ipsw --build 20E246 -d iPad6,3 --kernel
	ipsw download ipsw --build 20E246 -d iPad6,11 --kernel
	cd ..
	"$HKERNELFWEXTRACTOR" "${SCRIPT_PATH}/firmware" $(find kernels -type f)
	popd
	echo "[*] Firmware at ${SCRIPT_PATH}/firmware";
	rm -rf "$WORK"

	exit 0
}

remote_boot()
{
	WORK="$(mktemp -d)";

	mkdir -p "$SCRIPT_PATH/cache"

	if [ "$1" = "prep" ]; then
		prepare_boot_files
	elif [ "$1" = "boot" ]; then
		boot_device "$@"
	fi

	rm -rf "$WORK"
}

GASTER="${SCRIPT_PATH}/vendor/gaster/gaster"
HBOOTPATCHER="${SCRIPT_PATH}/vendor/hBootPatcher/hBootPatcher"
HKERNELFWEXTRACTOR="${SCRIPT_PATH}/vendor/hKernelFWExtractor/hKernelFWExtractor"
MAKE="$(make_check)"

trap err_handler EXIT

root_check "$@"
check_cmd "irecovery" "http://github.com/libimobiledevice/libirecovery";
check_cmd "ipsw" "https://github.com/blacktop/ipsw";
check_cmd "clang"
check_cmd "xxd"
check_cmd "git"
usb_check
update_submodules
vendor_check "gaster"
gaster_build
vendor_check "hBootPatcher"
hBootPatcher_build
vendor_check "hKernelFWExtractor"
hKernelFWExtractor_build
usage_check "$@"
get_firmware "$@"
dfu_poll
gaster_pwn
get_device_info
remote_boot "$@"
