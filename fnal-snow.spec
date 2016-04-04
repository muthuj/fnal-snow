Name:           fnal-snow
Summary:        Scripts and libraries to interact with Service Now @ FNAL
Version:        1.0.4
Release:        1%{?dist}
Packager:       Tim Skirvin <tskirvin@fnal.gov>
Group:          Applications/System
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Source0:        %{name}-%{version}-%{release}.tar.gz
BuildArch:      noarch

Requires:       perl perl-MIME-Lite perl-YAML perl-ServiceNow
BuildRequires:  rsync
Vendor:         FNAL USCMS-T1
License:        BSD
Distribution:   CMS
URL:            http://www.fnal.gov/

%description
Installs scripts and tools that provide an interface to the Fermi Service
Now interface.

%prep

%setup -c -q -n %{name}-%{version}-%{release}

%build

%install
mkdir -p ${RPM_BUILD_ROOT}/usr/share/perl5/vendor_perl
rsync -Crlpt ./usr ${RPM_BUILD_ROOT}
rsync -Crlpt ./lib/ ${RPM_BUILD_ROOT}/usr/share/perl5/vendor_perl

mkdir -p ${RPM_BUILD_ROOT}/usr/share/man/man1
for i in `ls usr/bin`; do
    pod2man --section 1 --center="System Commands" usr/bin/${i} \
        > ${RPM_BUILD_ROOT}/usr/share/man/man1/${i}.1 ;
done

mkdir -p ${RPM_BUILD_ROOT}/usr/share/man/man3
pod2man --section 3 --center="Perl Documentation" lib/FNAL/SNOW.pm \
        > ${RPM_BUILD_ROOT}/usr/share/man/man3/FNAL::SNOW.3
pod2man --section 3 --center="Perl Documentation" lib/FNAL/SNOW/Config.pm \
        > ${RPM_BUILD_ROOT}/usr/share/man/man3/FNAL::SNOW::Config.3

%clean
# Adding empty clean section per rpmlint.  In this particular case, there is 
# nothing to clean up as there is no build process

%files
%defattr(-,root,root)
/usr/bin/*
/usr/share/man/man1/*
/usr/share/man/man3/*
/usr/share/perl5/vendor_perl/FNAL/*

%changelog
* Mon Apr 04 2016   Tim Skirvin <tskirvin@fnal.gov>   1.0.4-1
- SNOW.pm - fixed some date subroutines

* Mon Mar 28 2016   Tim Skirvin <tskirvin@fnal.gov>   1.0.4-0
- more speed improvements (dropping empty name lookups)
- RITM searching improvements (e.g. they actually work, for now)

* Mon Mar 28 2016   Tim Skirvin <tskirvin@fnal.gov>   1.0.3-0
- added PRJTASK support (read-only, only in lists)

* Mon Mar 28 2016   Tim Skirvin <tskirvin@fnal.gov>   1.0.2-0
- name caching works (should speed things up dramatically)
- tweaked 'unresolved' standards to better match FNAL instance
- better debugging

* Tue Mar 10 2015   Tim Skirvin <tskirvin@fnal.gov>   1.0.1-0
- snow-ticket-create - removing some old debugging output
- changing to 'x.y.z' versioning

* Fri Dec 19 2014   Tim Skirvin <tskirvin@fnal.gov>   0-6
- snow-to-nagios - service tickets are no longer auto-closed

* Wed Jul 30 2014   Tim Skirvin <tskirvin@fnal.gov>   0-5
- snow-ticket-unassign - new script
- snow-ticket-journal - added '--stdin' for getting text
- snow-ticket-resolve - added '--stdin' for getting text

* Fri Jul 25 2014   Tim Skirvin <tskirvin@fnal.gov>   0-4
- snow-ticket-create now exists
- snow-ticket-list and snow-ticket now do a better job with requester
  information
- snow-ticket-list reports on usernames with uids
- snow-ticket-assign confirms user/group memberships before assignments
- FNAL::SNOW user/group scripts are now just more useful.

* Wed Jul 23 2014   Tim Skirvin <tskirvin@fnal.gov>   0-3
- adding create() and tkt_create() functions
- general code cleanup

* Mon Jul 17 2014   Tim Skirvin <tskirvin@fnal.gov>   0-2
- cleanup and adding man pages

* Mon Jul 17 2014   Tim Skirvin <tskirvin@fnal.gov>   0-1
- initial packaging
