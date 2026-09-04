#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="${root_dir}/native_sources.lock"
latest=false

if [[ "${1:-}" == "--latest" ]]; then
	latest=true
elif [[ $# -gt 0 ]]; then
	echo "Usage: $0 [--latest]" >&2
	exit 64
fi

# shellcheck source=/dev/null
source "${lock_file}"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mariannmt-sources.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT
mkdir -p "${work_dir}/third_party"

clone_source() {
	local repository="$1"
	local revision="$2"
	local destination="$3"
	git clone --filter=blob:none --no-checkout "${repository}" "${destination}"
	git -C "${destination}" checkout "${revision}"
	git -C "${destination}" submodule update --init --recursive --depth 1
}

if [[ "${latest}" == true ]]; then
	ENGINE_REVISION="$(git ls-remote "${ENGINE_REPOSITORY}" HEAD | awk '{print $1}')"
	CLD2_REVISION="$(git ls-remote "${CLD2_REPOSITORY}" HEAD | awk '{print $1}')"
fi

clone_source "${ENGINE_REPOSITORY}" "${ENGINE_REVISION}" \
	"${work_dir}/third_party/bergamot-translator"
clone_source "${CLD2_REPOSITORY}" "${CLD2_REVISION}" \
	"${work_dir}/third_party/cld2"

if ! git -C "${work_dir}" apply \
	"${root_dir}/third_party/patches/00-bergamot-translator.patch"; then
	echo "The portability patch does not apply to these revisions." >&2
	echo "No repository files were replaced." >&2
	exit 1
fi

find "${work_dir}/third_party" \
	\( -name .git -o -name .gitmodules \) -prune -exec rm -rf {} +

# Nested ignore rules describe upstream development artifacts and cause pub.dev
# to warn about vendored source files that are intentionally checked in.
find "${work_dir}/third_party" -name .gitignore -type f -delete

for relative_path in \
	"bergamot-translator/.github" \
	"bergamot-translator/doc" \
	"bergamot-translator/examples" \
	"bergamot-translator/wasm" \
	"bergamot-translator/bergamot-translator-tests" \
	"bergamot-translator/3rd_party/marian-dev/.github" \
	"bergamot-translator/3rd_party/marian-dev/contrib" \
	"bergamot-translator/3rd_party/marian-dev/doc" \
	"bergamot-translator/3rd_party/marian-dev/examples" \
	"bergamot-translator/3rd_party/marian-dev/regression-tests" \
	"bergamot-translator/3rd_party/marian-dev/scripts" \
	"bergamot-translator/3rd_party/marian-dev/wasm" \
	"bergamot-translator/3rd_party/marian-dev/src/examples" \
	"bergamot-translator/3rd_party/marian-dev/src/tests" \
	"bergamot-translator/3rd_party/pybind11" \
	"bergamot-translator/bindings" \
	"bergamot-translator/src/tests" \
	"cld2/docs"; do
	rm -rf "${work_dir}/third_party/${relative_path}"
done

# Retain the compact CLD2 tables selected by third_party/cmake/cld2.cmake and
# discard alternative table sets, generators, tests, and standalone tools.
find "${work_dir}/third_party/cld2/internal" -type f \
	\( -name '*unittest*' -o -name 'compile*.sh' -o -name 'clean.sh' \
	   -o -name 'cld2_dynamic_*' -o -name 'cld2_do_score.cc' \
	   -o -name 'cld2_generated_deltaocta0122.cc' \
	   -o -name 'cld2_generated_deltaocta0527.cc' \
	   -o -name 'cld2_generated_distinctocta0122.cc' \
	   -o -name 'cld2_generated_distinctocta0527.cc' \
	   -o -name 'cld2_generated_octa2_dummy.cc' \
	   -o -name 'cld2_generated_quad0122.cc' \
	   -o -name 'cld2_generated_quad0720.cc' \
	   -o -name 'cld2_generated_quadchrome_16.cc' \
	   -o -name 'cld_generated_cjk_delta_bi_32.cc' \
	   -o -name 'cld_generated_score_quad_octa_0122*.cc' \
	   -o -name 'cld_generated_score_quad_octa_1024_256.cc' \
	   -o -name 'scoreutf8text.cc' -o -name '*.utf8.gz' \) -delete

rm -rf "${root_dir}/third_party/bergamot-translator" \
	"${root_dir}/third_party/cld2"
mv "${work_dir}/third_party/bergamot-translator" \
	"${root_dir}/third_party/bergamot-translator"
mv "${work_dir}/third_party/cld2" "${root_dir}/third_party/cld2"

if [[ "${latest}" == true ]]; then
	awk -v engine="${ENGINE_REVISION}" -v cld2="${CLD2_REVISION}" '
		/^ENGINE_REVISION=/ {$0="ENGINE_REVISION=" engine}
		/^CLD2_REVISION=/ {$0="CLD2_REVISION=" cld2}
		{print}
	' "${lock_file}" > "${lock_file}.tmp"
	mv "${lock_file}.tmp" "${lock_file}"
fi

echo "Vendored native sources refreshed."
echo "Engine: ${ENGINE_REVISION}"
echo "CLD2:   ${CLD2_REVISION}"
