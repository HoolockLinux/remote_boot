#!/usr/bin/env bash

set -e;
OS="$(uname -s)"

SCRIPT_PATH="$(dirname -- "${BASH_SOURCE[0]}")"

if [ "$OS" != "Darwin" ] && [ "$(id -u)" != "0" ]; then
	echo "[-] Please run as root";
	exit 1;
fi

check_cmd()
{
	if [ "$(command -v "$1")" = "" ]; then
		echo "[-] $1 not found!";
		echo "[-] $1 project URL: $2";
		exit 1;
	fi
}

err_handler()
{
	echo "[-] An error occured";
	exit 1;
}

trap err_handler EXIT

check_cmd "irecovery" "http://github.com/libimobiledevice/libirecovery";
check_cmd "ipsw" "https://github.com/blacktop/ipsw";
check_cmd "hBootPatcher" "https://github.com/HoolockLinux/hBootPatcher";
check_cmd "gaster" "https://github.com/verygenericname/gaster";

if [ "$1" != "prep" ] && [ "$1" != "boot" ] || ([ "$1" = "boot" ] && ([ "$2" = "" ] || [ "$3" = "" ]);); then
	printf "Usage: \t$0\n\tprep\t\t\t\t\t\tfor preparing bootchain files\n";
	printf "\tboot <m1n1-idevice.macho> <monitor-stub.macho>\tBoot m1n1\n";
	exit 1;
fi


mkdir -p "$SCRIPT_PATH/cache"

echo "[*] Waiting for device in DFU mode"

if [ "$OS" = "Darwin" ]; then
	while ! system_profiler SPUSBDataType SPUSBHostDataType | grep -qF ' Apple Mobile Device (DFU Mode)'; do
		sleep 1;
	done
else
	while ! lsusb 2> /dev/null | grep -qF ' Apple, Inc. Mobile Device (DFU Mode)'; do
		sleep 1;
	done
fi

echo "[*] Detected device"

gaster pwn
gaster decrypt_kbag 000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 > /dev/null || true

CPID="$(irecovery -q | grep CPID | sed -E 's/^CPID: (.*)$/\1/')"
MODEL="$(irecovery -q | grep MODEL | sed -E 's/^MODEL: (.*)$/\1/')"
PRODUCT="$(irecovery -q | grep PRODUCT | sed -E 's/^PRODUCT: (.*)$/\1/')"
WORK="$(mktemp -d)";

if [ "$CPID" = "0x8960" ] || [ "$CPID" = "0x7000" ] ||[ "$CPID" = "0x7001" ] || [ "$CPID" = "0x8000" ] || [ "$CPID" = "0x8001" ] || [ "$CPID" = "0x8003" ]; then
	two_stage="1";
else
	two_stage="0";
fi

if [ "$1" = "boot" ]; then
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

	gaster reset
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

elif [ "$1" = "prep" ]; then
	ipsw_dl_args=""

	if [ "$CPID" = "0x8012" ]; then
		ipsw_dl_args="download ipsw --ibridge -d $PRODUCT -m $MODEL --version 7.6"
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

	gaster decrypt "$IBSS_PATH" "$WORK/iBSS_${MODEL}_${PRODUCT}.bin"

	if [ "$two_stage" = "1" ]; then
		gaster decrypt "$IBEC_PATH" "$WORK/iBEC_${MODEL}_${PRODUCT}.bin"
	fi

	ipsw img4 im4p extract -o "$WORK/DeviceTree_${MODEL}_${PRODUCT}.bin" "$DTRE_PATH"

	hBootPatcher -airs "$WORK/iBSS_${MODEL}_${PRODUCT}.bin" "$WORK/iBSS_${MODEL}_${PRODUCT}_patched.bin";

	if [ "$two_stage" = "1" ]; then
		hBootPatcher -airs "$WORK/iBEC_${MODEL}_${PRODUCT}.bin" "$WORK/iBEC_${MODEL}_${PRODUCT}_patched.bin";
	fi

	popd

	ipsw img4 create --input "$WORK/iBSS_${MODEL}_${PRODUCT}_patched.bin" --type ibss --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/iBSS_${MODEL}_${PRODUCT}.img4"

	if [ "$two_stage" = "1" ]; then
		ipsw img4 create --input "$WORK/iBEC_${MODEL}_${PRODUCT}_patched.bin" --type ibec --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/iBEC_${MODEL}_${PRODUCT}.img4"
	fi
	ipsw img4 create --input "$WORK/DeviceTree_${MODEL}_${PRODUCT}.bin" --type rdtr --im4m "${SCRIPT_PATH}/im4m/${CPID}.im4m" --output "${SCRIPT_PATH}/cache/RestoreDeviceTree_${MODEL}_${PRODUCT}.img4"
fi
rm -rf "$WORK"
