#!/bin/zsh
set -euo pipefail

readonly brand_dir="${0:A:h}"
readonly source_svg="${brand_dir}/VoxHearthIcon.svg"
readonly output_icns="${brand_dir}/VoxHearth.icns"

for tool in rsvg-convert sips iconutil file perl awk; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "Missing required icon tool: ${tool}"
        exit 1
    fi
done

if [[ ! -s "${source_svg}" ]]; then
    print -u2 "Missing source icon: ${source_svg}"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/voxhearth-icon.XXXXXX")"
readonly work_dir
cleanup() {
    if [[ "${KEEP_ICON_WORK:-0}" == "1" ]]; then
        print "Kept icon work directory: ${work_dir}"
    else
        rm -rf -- "${work_dir}"
    fi
}
trap cleanup EXIT

readonly iconset_dir="${work_dir}/VoxHearth.iconset"
readonly staged_icns="${work_dir}/VoxHearth.icns"
readonly verified_iconset_dir="${work_dir}/Verified.iconset"
mkdir -p "${iconset_dir}"

render_png() {
    local pixel_size="$1"
    local filename="$2"
    local unprofiled_png="${work_dir}/render-${pixel_size}.png"
    rsvg-convert \
        --width "${pixel_size}" \
        --height "${pixel_size}" \
        --output "${unprofiled_png}" \
        "${source_svg}"
    sips \
        --matchTo "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
        "${unprofiled_png}" \
        --out "${iconset_dir}/${filename}" \
        >/dev/null
    rm -f -- "${unprofiled_png}"
}

# Modern ICNS readers use ic11/ic12 as the logical 16px/32px assets and
# downsample them on 1x displays. Avoid icp4/icp5: macOS 26 iconutil corrupts
# those PNG-backed chunks when decoding them, while all modern chunks below
# round-trip cleanly.
render_png 32 icon_16x16@2x.png
render_png 64 icon_32x32@2x.png
render_png 128 icon_128x128.png
render_png 256 icon_128x128@2x.png
render_png 256 icon_256x256.png
render_png 512 icon_256x256@2x.png
render_png 512 icon_512x512.png
render_png 1024 icon_512x512@2x.png

# macOS 26's iconutil encoder rejects even iconsets that its own decoder
# produces. Write the documented modern PNG-backed ICNS chunks directly,
# then use iconutil below as an independent decoder/round-trip check.
perl -e '
    use strict;
    use warnings;

    my $output = shift @ARGV;
    my $body = q{};

    while (@ARGV) {
        my $type = shift @ARGV;
        my $path = shift @ARGV;
        local $/;
        open my $input, "<:raw", $path or die "$path: $!\n";
        my $png = <$input>;
        close $input or die "$path: $!\n";
        $body .= pack("a4N", $type, length($png) + 8) . $png;
    }

    open my $icon, ">:raw", $output or die "$output: $!\n";
    print {$icon} pack("a4N", "icns", length($body) + 8), $body
        or die "$output: $!\n";
    close $icon or die "$output: $!\n";
' "${staged_icns}" \
    ic11 "${iconset_dir}/icon_16x16@2x.png" \
    ic12 "${iconset_dir}/icon_32x32@2x.png" \
    ic07 "${iconset_dir}/icon_128x128.png" \
    ic13 "${iconset_dir}/icon_128x128@2x.png" \
    ic08 "${iconset_dir}/icon_256x256.png" \
    ic14 "${iconset_dir}/icon_256x256@2x.png" \
    ic09 "${iconset_dir}/icon_512x512.png" \
    ic10 "${iconset_dir}/icon_512x512@2x.png"

iconutil --convert iconset "${staged_icns}" --output "${verified_iconset_dir}"

for image_spec in \
    icon_16x16@2x.png:32 \
    icon_32x32@2x.png:64 \
    icon_128x128.png:128 \
    icon_128x128@2x.png:256 \
    icon_256x256.png:256 \
    icon_256x256@2x.png:512 \
    icon_512x512.png:512 \
    icon_512x512@2x.png:1024; do
    image_name="${image_spec%%:*}"
    expected_size="${image_spec##*:}"
    verified_image="${verified_iconset_dir}/${image_name}"

    if [[ ! -s "${verified_image}" ]]; then
        print -u2 "ICNS round-trip omitted required image: ${image_name}"
        exit 1
    fi

    actual_width="$(sips -g pixelWidth "${verified_image}" | awk '/pixelWidth:/ { print $2 }')"
    actual_height="$(sips -g pixelHeight "${verified_image}" | awk '/pixelHeight:/ { print $2 }')"
    if [[ "${actual_width}" != "${expected_size}" || "${actual_height}" != "${expected_size}" ]]; then
        print -u2 "Unexpected round-trip dimensions for ${image_name}: ${actual_width}x${actual_height}"
        exit 1
    fi
done

readonly file_description="$(file -b "${staged_icns}")"
if [[ "${file_description}" != "Mac OS X icon,"* ]]; then
    print -u2 "Unexpected ICNS file type: ${file_description}"
    exit 1
fi

mv -f "${staged_icns}" "${output_icns}"

file "${output_icns}"
shasum -a 256 "${output_icns}"
