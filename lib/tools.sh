#!/bin/bash

# Dynamic package build selection. Typically, X-Env Triggers set defined
# variables which map to the package registry below. These compoments are
# built and installed as prerequisites in a reusable mini-sysroot.
# Can scale as needed, eg move away from bash array to file. Main thing
# is to retain functionality: vars -> registry -> selection -> action
#
# See registry.defs
readonly -a IG_TOOLS_REGISTRY=(
   "IG_ENABLE_HOST_BDEBSTRAP|y|bdebstrap"
   "IG_ENABLE_HOST_GENIMAGE|y|genimage"
   "IG_ENABLE_HOST_ZSTD|y|zstd"
   "IG_ENABLE_HOST_EROFS_UTILS|y|erofs-utils"
)

collect_build_deps() {
   local envfile="${1:?missing env file}"
   local packages=
   local var value pkg

   for entry in "${IG_TOOLS_REGISTRY[@]}"; do
      IFS='|' read -r var value pkg <<< "$entry"
      if value_read=$(get_var "$var" "$envfile") && [[ "$value_read" == "$value" ]]; then
         packages+=("$pkg")
      fi
   done
   echo "${packages[*]}"
}


bootstrap_build_tools() {
   : "${ctx[FINALENV]?missing ctx[FINALENV]}"
   : "${IGconf_sys_workroot?missing IGconf_sys_workroot}"
   : "${DEB_BUILD_GNU_TYPE?missing DEB_BUILD_GNU_TYPE}"
   : "${IGconf_sys_buildroot?missing IGconf_sys_buildroot}"

   local tools=( $(collect_build_deps "${ctx[FINALENV]}") )
   local destdir="${IGconf_sys_workroot}/${DEB_BUILD_GNU_TYPE}"
   local prefix=/usr
   local start=$SECONDS
   local runtime_path="${IGconf_sys_buildroot}/host/${DEB_BUILD_GNU_TYPE}/usr"

   runenv "${ctx[FINALENV]}" \
      make -s -j"$(nproc)" -C "${IGTOP}/package" "${tools[@]}" \
      PKG_DESTDIR="$destdir" PKG_PREFIX="$prefix"

   # Package recipes prune shared sysroot paths, so clean them after all installs.
   rm -rf \
      "$runtime_path"/lib/*.a \
      "$runtime_path"/lib/*.la \
      "$runtime_path"/include \
      "$runtime_path"/lib/pkgconfig \
      "$runtime_path"/lib/python*/dist-packages/*.dist-info \
      "$runtime_path"/lib/python*/dist-packages/*.data \
      "$runtime_path"/lib/python*/dist-packages/test* \
      "$runtime_path"/lib/python*/dist-packages/__pycache__ \
      "$runtime_path"/share/doc \
      "$runtime_path"/share/man

   local elapsed=$(( SECONDS - start ))
   msg "Building host support took $((elapsed / 60))m$((elapsed % 60))s"

   # prepend host tool paths
   PATH="${destdir}${prefix}/local/bin:${destdir}${prefix}/bin:${PATH}"
   export PATH

   local pyver
   pyver=$(python3 -c 'import sysconfig; print("python"+sysconfig.get_python_version())')
   PYTHONPATH="${destdir}${prefix}/local/lib/${pyver}/dist-packages:${destdir}${prefix}/lib/${pyver}/dist-packages:${PYTHONPATH:-}"
   export PYTHONPATH
}
