#!/bin/bash
###
### Build treesitter and its friends
###
### Usage:
###   build.sh [options] [languages]
###
### Options:
###   -a, --add     Add one (and only one) new language.
###   -u, --update  Update to the latest tag.
###   -f, --force   Force add or update.
###
### Languages could be:
###   1. core: treesitter itself.
###   2. LANG: build for given language, such as c/cpp/java...
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
FORCE=
ADD=

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
        markdown)
            build-lang-in-dir "${repo}/tree-sitter-markdown" markdown
            build-lang-in-dir "${repo}/tree-sitter-markdown-inline" markdown-inline
            ;;
        *) build-lang-in-dir "$repo" "$lang" ;;
    esac
}

update-to-latest-tag() {
    echo "======================== Updating: $(basename "${PWD}") ========================"
    git reset HEAD --hard
    git fetch origin
    local tag=$(git describe --tags "$(git rev-list --tags --max-count=1)")
    if [[ -n "${tag}" ]]; then
        git checkout "${tag}"
        exit $?
    else
        git reset origin/HEAD
        exit $?
    fi
}

while [ $# -gt 0 ] && [[ "$1" = -* ]]; do
    case "$1" in
        -f | --force) FORCE=1 ;;
        -u | --update) git submodule foreach "${SCRIPT}" -U ;;
        -U) update-to-latest-tag ;; # internal use only
        -a | --add) ADD="$2" ; shift ;;
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

if [[ -n "${ADD}" ]]; then
    [[ "$ADD" =~ ^(git@|https://) ]] || die "Bad address: $2"
    base=${ADD##*/}
    repodir="${base%.*}"
    pushd "${TOPDIR}" > /dev/null
    commands=(git submodule add)
    [[ -n "${FORCE}" ]] && commands+=("--force")
    commands+=("$ADD" "$repodir")
    "${commands[@]}" || die "Submodule add"
    cd "$repodir" && update-to-latest-tag
    popd > /dev/null
    build-language "$(echo "$repodir" | sed -E 's#tree-sitter/tree-sitter-(.*?).git#\1#g')"
else
    if [ $# -ne 0 ]; then
        for item in "$@"; do
            case "$item" in
                core) build-tree-sitter ;;
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
                *) build-language "${item//tree-sitter-/}" ;;
            esac
        done
    fi
fi
