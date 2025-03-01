#!/bin/bash
###
### Build treesitter and its friends
###
### Usage:
###   build.sh [options] [languages]
###
### Options:
###   -h, --help    Show this message.
###   -a, --add     Add one (and only one) new language.
###   -c, --core    Build treesitter library only.
###   -d, --debug   Show debug messages.
###   -u, --update  Update to the latest tag
###
###  Without specifying any language, everything will be built.
###
### More parsers can be found in:
###   https://github.com/tree-sitter/tree-sitter/blob/master/docs/index.md
###

help() {
    sed -rn 's/^### ?//;T;p' "$0"
    exit 0
}

SCRIPT=$(realpath "$0"||grealpath "$0")
TOPDIR=${SCRIPT%/*}
C_ARGS=(-fPIC -c -I"${HOME}"/.local/include -I.)

echo "CC: ${CC:=cc}"
echo "CXX: ${CXX:=c++}"

case $(uname) in
    "Darwin") soext="dylib" ;;
    *"MINGW"*) soext="dll" ;;
    *) soext="so" ;;
esac

die() {
    set +xe
    echo "================================ DIE ===============================" >&2
    echo >&2 "$*"
    echo >&2 "Call stack:"
    local n=$((${#BASH_LINENO[@]} - 1))
    local i=0
    while [ $i -lt $n ]; do
        echo >&2 "    [$i] -- line ${BASH_LINENO[i]} -- ${FUNCNAME[i + 1]}"
        i=$((i + 1))
    done
    echo >&2 "================================ END ==============================="

    [[ $- == *i* ]] && return 1 || exit 1
}

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
        *) build-lang-in-dir "$repo" "$lang" ;;
    esac
}

CORE_ONLY=

build-all-langs() {
    echo "Building all ..."
    pushd "${TOPDIR}" || die "change dir"

    for file in *; do
        if [[ ! -d $file ]]; then
            echo "Skipping file: $file"
            continue
        fi

        if [[ "$file" = "tree-sitter" ]]; then
            echo "Skipping directory: $file"
            continue
        fi

        echo "Building ${file}"
        build-language "${file//tree-sitter-/}"
    done
}

update-to-lastest-tag() {
    echo "======================== Updating: $(basename "${PWD}") ========================"
    git fetch origin
    local tag=$(git describe --tags "$(git rev-list --tags --max-count=1)")
    git checkout "${tag}"
    exit $?
}

while [ $# -gt 0 ] && [[ "$1" = -* ]]; do
    case "$1" in
        -h | --help) help 1 ;;
        -d | --debug) pdebug_setup ;;
        -c | --core) CORE_ONLY=1 ;;
        -u | --update) git submodule foreach "${SCRIPT}" -U ;;
        -U) update-to-lastest-tag ;; # internal use only
        -a | --add)
            [[ "$2" =~ ^(git@|https://) ]] || die "Bad address: $2"
            url="$2" && shift
            base=${url##*/}
            repodir=tree-sitter/"${base%.*}"
            pushd "${TOPDIR}"/.. > /dev/null
            git submodule add "$url" "$repodir" || die "Submodule add"
            cd "$repodir" && update-to-lastest-tag
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

if [[ -n "${CORE_ONLY}" ]]; then
    build-tree-sitter
    exit $?
fi

if [ $# -ne 0 ]; then
    for lang in "$@"; do
        build-language "${lang}"
    done
else
    build-tree-sitter || die "Failed to build tree-sitter library."
    build-all-langs || die "Failed to build parser."
fi
