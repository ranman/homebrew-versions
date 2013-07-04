require 'formula'

class Gcc47 < Formula
  def arch
    if Hardware::CPU.type == :intel
      if MacOS.prefer_64_bit?
        'x86_64'
      else
        'i686'
      end
    elsif Hardware::CPU.type == :ppc
      if MacOS.prefer_64_bit?
        'powerpc64'
      else
        'powerpc'
      end
    end
  end

  def osmajor
    `uname -r`.chomp
  end

  homepage 'http://gcc.gnu.org'
  url 'http://ftpmirror.gnu.org/gcc/gcc-4.7.3/gcc-4.7.3.tar.bz2'
  mirror 'http://ftp.gnu.org/gnu/gcc/gcc-4.7.3/gcc-4.7.3.tar.bz2'
  sha1 '69e02737bd6e1a7c6047d801600d39c32b9427ca'

  head 'svn://gcc.gnu.org/svn/gcc/branches/gcc-4_7-branch'

  option 'enable-cxx', 'Build the g++ compiler'
  option 'enable-fortran', 'Build the gfortran compiler'
  option 'enable-java', 'Buld the gcj compiler'
  option 'enable-objc', 'Enable Objective-C language support'
  option 'enable-objcxx', 'Enable Objective-C++ language support'
  option 'enable-go', 'Enable Go language support'
  option 'enable-all-languages', 'Enable all compilers and languages, except Ada'
  option 'enable-nls', 'Build with native language support (localization)'
  option 'enable-profiled-build', 'Make use of profile guided optimization when bootstrapping GCC'
  option 'enable-multilib', 'Build with multilib support'

  depends_on 'gmp4'
  depends_on 'libmpc08'
  depends_on 'mpfr2'
  depends_on 'ppl011'
  depends_on 'cloog-ppl015'
  depends_on 'ecj' if build.include? 'enable-java' or build.include? 'enable-all-languages'

  # Import patches from macports:
  # https://trac.macports.org/browser/trunk/dports/lang/gcc47/files/gcc-PR-53453.patch
  def patches; DATA; end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete 'LD'

    if build.include? 'enable-all-languages'
      # Everything but Ada, which requires a pre-existing GCC Ada compiler
      # (gnat) to bootstrap. GCC 4.6.0 add go as a language option, but it is
      # currently only compilable on Linux.
      languages = %w[c c++ fortran java objc obj-c++ go]
    else
      # The C compiler is always built, but additional defaults can be added
      # here.
      languages = %w[c]

      languages << 'c++' if build.include? 'enable-cxx'
      languages << 'fortran' if build.include? 'enable-fortran'
      languages << 'java' if build.include? 'enable-java'
      languages << 'objc' if build.include? 'enable-objc'
      languages << 'obj-c++' if build.include? 'enable-objcxx'
      languages << 'go' if build.include? 'enable-go'
    end

    # Sandbox the GCC lib, libexec and include directories so they don't wander
    # around telling small children there is no Santa Claus. This results in a
    # partially keg-only brew following suggestions outlined in the "How to
    # install multiple versions of GCC" section of the GCC FAQ:
    #     http://gcc.gnu.org/faq.html#multiple
    gcc_prefix = prefix + 'gcc'

    args = [
      "--build=#{arch}-apple-darwin#{osmajor}",
      # Sandbox everything...
      "--prefix=#{gcc_prefix}",
      # ...except the stuff in share...
      "--datarootdir=#{share}",
      # ...and the binaries...
      "--bindir=#{bin}",
      # ...which are tagged with a suffix to distinguish them.
      "--enable-languages=#{languages.join(',')}",
      "--program-suffix=-#{version.to_s.slice(/\d\.\d/)}",
      "--with-gmp=#{Formula.factory('gmp4').opt_prefix}",
      "--with-mpfr=#{Formula.factory('mpfr2').opt_prefix}",
      "--with-mpc=#{Formula.factory('libmpc08').opt_prefix}",
      "--with-ppl=#{Formula.factory('ppl011').opt_prefix}",
      "--with-cloog=#{Formula.factory('cloog-ppl015').opt_prefix}",
      "--with-system-zlib",
      "--enable-libstdcxx-time=yes",
      "--enable-stage1-checking",
      "--enable-checking=release",
      "--enable-lto",
      # a no-op unless --HEAD is built because in head warnings will raise errs.
      "--disable-werror"
    ]

    # "Building GCC with plugin support requires a host that supports
    # -fPIC, -shared, -ldl and -rdynamic."
    args << "--enable-plugin" if MacOS.version > :tiger

    args << '--disable-nls' unless build.include? 'enable-nls'

    if build.include? 'enable-java' or build.include? 'enable-all-languages'
      args << "--with-ecj-jar=#{Formula.factory('ecj').opt_prefix}/share/java/ecj.jar"
    end

    if build.include? 'enable-multilib'
      args << '--enable-multilib'
    else
      args << '--disable-multilib'
    end

    mkdir 'build' do
      unless MacOS::CLT.installed?
        # For Xcode-only systems, we need to tell the sysroot path.
        # 'native-system-header's will be appended
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=#{MacOS.sdk_path}"
      end

      system '../configure', *args

      if build.include? 'enable-profiled-build'
        # Takes longer to build, may bug out. Provided for those who want to
        # optimise all the way to 11.
        system 'make profiledbootstrap'
      else
        system 'make bootstrap'
      end

      # At this point `make check` could be invoked to run the testsuite. The
      # deja-gnu and autogen formulae must be installed in order to do this.

      system 'make install'

      # Remove conflicting manpages in man7
      man7.rmtree
    end
  end
end

__END__
http://gcc.gnu.org/ml/gcc-patches/2012-06/msg01181.html
http://gcc.gnu.org/bugzilla/show_bug.cgi?id=53453

diff -uNr gcc/config/darwin.h gcc/config/darwin.h
--- gcc-4.7.0/gcc/config/darwin.h	2012-02-16 03:21:46.000000000 -0500
+++ gcc-4.7.0/gcc/config/darwin.h	2012-06-08 08:54:25.000000000 -0400
@@ -356,7 +356,9 @@
      %{!Zbundle:%{pg:%{static:-lgcrt0.o}				    \
                      %{!static:%{object:-lgcrt0.o}			    \
                                %{!object:%{preload:-lgcrt0.o}		    \
-                                 %{!preload:-lgcrt1.o %(darwin_crt2)}}}}    \
+                                 %{!preload:-lgcrt1.o                       \
+                                 %:version-compare(>= 10.8 mmacosx-version-min= -no_new_main) \
+                                 %(darwin_crt2)}}}}    \
                 %{!pg:%{static:-lcrt0.o}				    \
                       %{!static:%{object:-lcrt0.o}			    \
                                 %{!object:%{preload:-lcrt0.o}		    \
@@ -379,7 +381,7 @@
 #define DARWIN_CRT1_SPEC						\
   "%:version-compare(!> 10.5 mmacosx-version-min= -lcrt1.o)		\
    %:version-compare(>< 10.5 10.6 mmacosx-version-min= -lcrt1.10.5.o)	\
-   %:version-compare(>= 10.6 mmacosx-version-min= -lcrt1.10.6.o)	\
+   %:version-compare(>< 10.6 10.8 mmacosx-version-min= -lcrt1.10.6.o)	\
    %{fgnu-tm: -lcrttms.o}"
 
 /* Default Darwin ASM_SPEC, very simple.  */
@@ -414,6 +416,8 @@
 
 #define TARGET_WANT_DEBUG_PUB_SECTIONS true
 
+#define TARGET_FORCE_AT_COMP_DIR true
+
 /* When generating stabs debugging, use N_BINCL entries.  */
 
 #define DBX_USE_BINCL
diff -uNr gcc/doc/tm.texi gcc/doc/tm.texi
--- gcc-4.7.0/gcc/doc/tm.texi	2012-01-26 16:48:27.000000000 -0500
+++ gcc-4.7.0/gcc/doc/tm.texi	2012-06-08 08:54:25.000000000 -0400
@@ -9487,6 +9487,10 @@
 True if the @code{.debug_pubtypes} and @code{.debug_pubnames} sections should be emitted.  These sections are not used on most platforms, and in particular GDB does not use them.
 @end deftypevr
 
+@deftypevr {Target Hook} bool TARGET_FORCE_AT_COMP_DIR
+True if the @code{DW_AT_comp_dir} attribute should be emitted for each  compilation unit.  This attribute is required for the darwin linker  to emit debug information.
+@end deftypevr
+
 @deftypevr {Target Hook} bool TARGET_DELAY_SCHED2
 True if sched2 is not to be run at its normal place.  This usually means it will be run as part of machine-specific reorg.
 @end deftypevr
diff -uNr gcc/doc/tm.texi.in gcc/doc/tm.texi.in
--- gcc-4.7.0/gcc/doc/tm.texi.in	2012-01-26 16:48:27.000000000 -0500
+++ gcc-4.7.0/gcc/doc/tm.texi.in	2012-06-08 08:54:25.000000000 -0400
@@ -9386,6 +9386,8 @@
 
 @hook TARGET_WANT_DEBUG_PUB_SECTIONS
 
+@hook TARGET_FORCE_AT_COMP_DIR
+
 @hook TARGET_DELAY_SCHED2
 
 @hook TARGET_DELAY_VARTRACK
diff -uNr gcc/dwarf2out.c gcc/dwarf2out.c
--- gcc-4.7.0/gcc/dwarf2out.c	2012-06-04 09:24:24.000000000 -0400
+++ gcc-4.7.0/gcc/dwarf2out.c	2012-06-08 08:54:25.000000000 -0400
@@ -22501,7 +22501,7 @@
   /* Add the name for the main input file now.  We delayed this from
      dwarf2out_init to avoid complications with PCH.  */
   add_name_attribute (comp_unit_die (), remap_debug_filename (filename));
-  if (!IS_ABSOLUTE_PATH (filename))
+  if (!IS_ABSOLUTE_PATH (filename) || targetm.force_at_comp_dir)
     add_comp_dir_attribute (comp_unit_die ());
   else if (get_AT (comp_unit_die (), DW_AT_comp_dir) == NULL)
     {
diff -uNr gcc/target.def gcc/target.def
--- gcc-4.7.0/gcc/target.def	2012-01-26 16:48:27.000000000 -0500
+++ gcc-4.7.0/gcc/target.def	2012-06-08 08:54:25.000000000 -0400
@@ -2748,6 +2748,13 @@
  bool, false)
 
 DEFHOOKPOD
+(force_at_comp_dir,
+ "True if the @code{DW_AT_comp_dir} attribute should be emitted for each \
+ compilation unit.  This attribute is required for the darwin linker \
+ to emit debug information.",
+ bool, false)
+
+DEFHOOKPOD
 (delay_sched2, "True if sched2 is not to be run at its normal place.  \
 This usually means it will be run as part of machine-specific reorg.",
 bool, false)
