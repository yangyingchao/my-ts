#!/bin/bash
###
### Build treesitter and its friends
###
### Usage:
###   build.sh [options] [languages]
###
### Options:
###   -a, --add     Add one (and only one) new language.
###   -u, --update  Update to the latest tag
###
### Languages could be:
###   1. core: treesitter itself.
###   2. mps:  build mps which is required by igc.
###   3. LANG: build for given language, such as c/cpp/java...
###
### Without specifying any language, everything will be built.
###
### More parsers can be found in:
###   https://github.com/tree-sitter/tree-sitter/blob/master/docs/index.md
###

source ~/.local/share/shell/yc-common.sh

export LANG=C

SCRIPT=$(realpath "$0" || grealpath "$0")
TOPDIR=${SCRIPT%/*}
C_ARGS=(-fPIC -c -I"${HOME}"/.local/include -I.)

echo "CC: ${CC:=cc}"
echo "CXX: ${CXX:=c++}"

case $(uname) in
    "Darwin") soext="dylib" ;;
    *"MINGW"*) soext="dll" ;;
    *) soext="so" ;;
esac

build-tree-sitter() {
    echo "======================== Building tree-sitter ========================"
    pushd "${TOPDIR}"/tree-sitter || die "change dir"
    make clean
    PREFIX=${HOME}/.local make -j8
    PREFIX=${HOME}/.local make install
    [ -f "${HOME}"/.local/lib/libtree-sitter.a ] && rm "${HOME}"/.local/lib/libtree-sitter.a
    popd > /dev/null 2>&1 || die "change dir"
    echo ""
}

build-mps() {
    echo "======================== Building MPS ========================"
    pushd "${TOPDIR}"/mps || die "change dir"
    git reset HEAD --hard
    while IFS= read -r -d '' fn; do
        sed -i 's/-Werror//g' "${fn}"
    done < <(find . -name "*.gmk" -print0)

    ./configure --prefix="${HOME}"/.local
    make -j8
    make install
    rm -rf "${HOME}"/.local/lib/libmps-debug.a
    git reset HEAD --hard
    popd > /dev/null 2>&1 || die "change dir"
    echo ""
}

build-lang-in-dir() {
    [ $# -ne 2 ] && die "Usage: build-lang-in-dir dir lang."

    pushd "$1" || die "change dir"

    local lang=$2

    echo "======================== Building language $lang ========================"

    local sourcedir="${PWD}/src"
    local libname="libtree-sitter-${lang}.${soext}"
    local targetname="${HOME}/.local/lib/${libname}"
    # emacs crashes when overwrite shared library script inside emacs..
    if [[ -n "${INSIDE_EMACS}" ]] && [[ -f "${targetname}" ]]; then
        targetname=${targetname}_new
    fi

    cp "${PWD}"/grammar.js "${sourcedir}"
    pushd "${sourcedir}" || die "Failed to change directory to ${sourcedir}"

    # clean up old files.
    rm ./*.o ./*."${soext}"*

    set -x
    ### Build
    [[ -f parser.c ]] || die "parser.c is not found."
    ${CC} "${C_ARGS[@]}" parser.c || die "Compile fail"

    if [ -f scanner.c ]; then
        ${CC} "${C_ARGS[@]}" scanner.c || die "Compile fail"
        ${CC} -fPIC -shared ./*.o -o "${libname}" || die "Link fail"
    elif [ -f scanner.cc ]; then
        ${CXX} "${C_ARGS[@]}" -c scanner.cc || die "Compile fail"
        ${CXX} -fPIC -shared ./*.o -o "${libname}" || die "Link fail"
    else
        ${CC} -fPIC -shared ./*.o -o "${libname}" || die "Link fail"
    fi

    set +x
    cp -aRfv "${libname}" "${targetname}"
    popd && popd || die "change dir"
    echo ""
}

build-language() {
    [ $# -ne 1 ] && die "Usage: build-language language."

    pushd "${TOPDIR}" || die "change dir"

    local lang=$1
    local repo="${TOPDIR}/tree-sitter-${lang}"

    case "${lang}" in
        go-mod) build-lang-in-dir "${repo}" gomod ;;
        php) build-lang-in-dir "${repo}/php" php ;;
        typescript)
            build-lang-in-dir "${repo}/typescript" typescript
            build-lang-in-dir "${repo}/tsx" tsx
            ;;
        *) build-lang-in-dir "$repo" "$lang" ;;
    esac
}

update-to-latest-tag() {
    echo "======================== Updating: $(basename "${PWD}") ========================"
    git reset HEAD --hard
    git fetch origin
    local tag=$(git describe --tags "$(git rev-list --tags --max-count=1)")
    git checkout "${tag}"
    exit $?
}

while [ $# -gt 0 ] && [[ "$1" = -* ]]; do
    case "$1" in
        -h | --help) help 1 ;;
        -d | --debug) pdebug_setup ;;
        -u | --update) git submodule foreach "${SCRIPT}" -U ;;
        -U) update-to-latest-tag ;; # internal use only
        -a | --add)
            [[ "$2" =~ ^(git@|https://) ]] || die "Bad address: $2"
            url="$2" && shift
            base=${url##*/}
            repodir="${base%.*}"
            pushd "${TOPDIR}" > /dev/null
            git submodule add "$url" "$repodir" || die "Submodule add"
            cd "$repodir" && update-to-latest-tag
            popd > /dev/null
            build-language "$(echo "$repodir" | sed -E 's#tree-sitter/tree-sitter-(.*?).git#\1#g')"
            ;;

        *)
            if [[ $1 = -* ]]; then
                echo "Unrecognized opt: $1, pass '--help' to show help message."
                exit 1
            else
                break
            fi
            ;;
    esac

    shift
done

pushd "${TOPDIR}" || die "change dir"

if [ $# -ne 0 ]; then
    for item in "$@"; do
        case "$item" in
            core) build-tree-sitter ;;
            mps) build-mps ;;
            *) build-language "$item" ;;
        esac
    done
else
    echo "Building all ..."
    pushd "${TOPDIR}" || die "change dir"

    for item in *; do
        if [[ ! -d $item ]]; then
            echo "Skipping file: $item"
            continue
        fi

        case "$item" in
            tree-sitter) build-tree-sitter ;;
            mps) build-mps ;;
            *) build-language "${item//tree-sitter-/}" ;;
        esac
    done
fi
