%{!?with_x:%define with_x 0}

Summary: A document formatting system
Name:	groff
Version: 1.20.1
Release: %{?release_prefix:%{release_prefix}.}1.10.%{?dist}%{!?dist:tizen}
VCS:     external/groff#Z910F_PROTEX_0625-2-g2440436a057df945142a1e25b45de0c577f549de
License: GPLv3+ and GFDL and BSC and MIT
Group: Applications/Publishing
URL: http://groff.ffii.org
Source0: ftp://ftp.gnu.org/gnu/groff/groff-%{version}.tar.gz
Patch1: groff-info-missing-x11.patch
Patch2: groff-japanese-charclass.patch
Patch3: groff-japanese-wcwidth.patch
 
Requires: /bin/mktemp
BuildRequires: bison zlib-devel 

%description
Groff is a document formatting system. Groff takes standard text and
formatting commands as input and produces formatted output. The
created documents can be shown on a display or printed on a printer.
Groff's formatting commands allow you to specify font type and size,
bold type, italic type, the number and size of columns on a page, and
more.

Groff can also be used to format man pages. If you are going to use
groff with the X Window System, you will also need to install the
groff-gxditview package.

%package perl
Summary: Parts of the groff formatting system that require Perl
Group: Applications/Publishing

%description perl
The groff-perl package contains the parts of the groff text processor
package that require Perl. These include the afmtodit font processor
for creating PostScript font files, the grog utility that can be used
to automatically determine groff command-line options, and the
troff-to-ps print filter.

%if %{with_x}
%package gxditview
Summary: An X previewer for groff text processor output
Group: Applications/Publishing
BuildRequires: imake xorg-x11-proto-devel libX11-devel libXaw-devel
BuildRequires: libXt-devel libXpm-devel libXext-devel

%description gxditview
Gxditview displays the groff text processor's output on an X Window
System display.
%endif

%package doc
Summary: Documentation for groff document formatting system
Group: Documentation
Requires: groff = %{version}-%{release}

%description doc
The groff-doc package includes additional documentation for groff
text processor package. It contains examples, documentation for PIC
language and documentation for creating PDF files.

%prep
%setup -q
%patch1 -p1
%patch2 -p1
%patch3 -p1

%build
%configure --enable-multibyte
make %{?_smp_mflags}

%install
rm -rf ${RPM_BUILD_ROOT}
mkdir -p ${RPM_BUILD_ROOT}%{_prefix} ${RPM_BUILD_ROOT}%{_infodir}
make install manroot=${RPM_BUILD_ROOT}%{_mandir} \
			bindir=%{buildroot}%{_bindir} \
			mandir=%{buildroot}%{_mandir} \
			prefix=%{buildroot}/usr \
			exec_prefix=%{buildroot}/usr \
			sbindir=%{buildroot}%{_exec_prefix}/sbin \
			sysconfdir=%{buildroot}/etc \
			datadir=%{buildroot}/usr/share \
			infodir=%{buildroot}/%{_prefix}/info \
			sysconfdir=%{buildroot}/etc \
			includedir=%{buildroot}/usr/include \
			libdir=%{buildroot}/%{_libdir} \
			libexecdir=%{buildroot}/usr/libexec \
			localstatedir=%{buildroot}/var \
			sharedstatedir=%{buildroot}/usr/com \
			infodir=%{buildroot}/usr/share/info
			
#install -m 644 doc/groff.info* ${RPM_BUILD_ROOT}/%{_infodir}
ln -s s.tmac ${RPM_BUILD_ROOT}%{_datadir}/groff/%version/tmac/gs.tmac
ln -s mse.tmac ${RPM_BUILD_ROOT}%{_datadir}/groff/%version/tmac/gmse.tmac
ln -s m.tmac ${RPM_BUILD_ROOT}%{_datadir}/groff/%version/tmac/gm.tmac
ln -s troff	${RPM_BUILD_ROOT}%{_bindir}/gtroff
ln -s tbl ${RPM_BUILD_ROOT}%{_bindir}/gtbl
ln -s pic ${RPM_BUILD_ROOT}%{_bindir}/gpic
ln -s eqn ${RPM_BUILD_ROOT}%{_bindir}/geqn
ln -s neqn ${RPM_BUILD_ROOT}%{_bindir}/gneqn
ln -s refer ${RPM_BUILD_ROOT}%{_bindir}/grefer
ln -s lookbib ${RPM_BUILD_ROOT}%{_bindir}/glookbib
ln -s indxbib ${RPM_BUILD_ROOT}%{_bindir}/gindxbib
ln -s soelim ${RPM_BUILD_ROOT}%{_bindir}/gsoelim
ln -s soelim ${RPM_BUILD_ROOT}%{_bindir}/zsoelim
ln -s nroff	${RPM_BUILD_ROOT}%{_bindir}/gnroff


find ${RPM_BUILD_ROOT}%{_bindir} -type f -o -type l | \
	grep -v afmtodit | grep -v grog | grep -v mdoc.samples |\
	grep -v mmroff |\
	grep -v gxditview |\
	sed "s|${RPM_BUILD_ROOT}||g" | sed "s|\.[0-9]|\.*|g" > groff-files

ln -sf doc.tmac $RPM_BUILD_ROOT%{_datadir}/groff/%version/tmac/docj.tmac
# installed, but not packaged in rpm
mkdir -p $RPM_BUILD_ROOT%{_datadir}/groff/%{version}/groffer/
chmod 755 $RPM_BUILD_ROOT%{_libdir}/groff/groffer/version.sh
mv $RPM_BUILD_ROOT%{_libdir}/groff/groffer/* $RPM_BUILD_ROOT/%{_datadir}/groff/%{version}/groffer/


%remove_docs

%clean
rm -rf ${RPM_BUILD_ROOT}

%files -f groff-files
%defattr(-,root,root,-)
%{_datadir}/groff

%files perl
%defattr(-,root,root,-)
%{_bindir}/grog
%{_bindir}/mmroff
%{_bindir}/afmtodit
%changelog
* Sat Jun 28 2014 SLP SCM <slpsystem.m@samsung.com> - None 
- PROJECT: external/groff
- COMMIT_ID: 2440436a057df945142a1e25b45de0c577f549de
- BRANCH: master
- PATCHSET_REVISION: 2440436a057df945142a1e25b45de0c577f549de
- CHANGE_OWNER: \"UkJung Kim\" <ujkim@samsung.com>
- PATCHSET_UPLOADER: \"UkJung Kim\" <ujkim@samsung.com>
- CHANGE_URL: http://slp-info.sec.samsung.net/gerrit/534342
- PATCHSET_REVISION: 2440436a057df945142a1e25b45de0c577f549de
- TAGGER: SLP SCM <slpsystem.m@samsung.com>
- Gerrit patchset approval info:
- UkJung Kim <ujkim@samsung.com> Verified : 1
- Newton Lee <newton.lee@samsung.com> Code-Review : 2
- Newton Lee <newton.lee@samsung.com> Verified : 1
- CHANGE_SUBJECT: Merged x86_64 support to master
- Merged x86_64 support to master
* Fri Jul 29 2011 Junfeng Dong <junfeng.dong@intel.com> - 1.20.1
- Import 1.20.1 for SLP.
* Sat Mar  6 2010 Anas Nashif <anas.nashif@intel.com> - 1.18.1.4
- Do not write new timestamp everytime we build
* Thu Dec 18 2008 Anas Nashif <anas.nashif@intel.com> 1.18.1.4
- Replace  mktemp with /bin/mktemp
* Thu Dec 11 2008 Anas Nashif <anas.nashif@intel.com> 1.18.1.4
- Use bison
* Fri Sep 12 2008 Yi Yang <yi.y.yang@intel.com> 1.18.1.4
- Mark man and info as %%doc and remove installation warnings of info files
