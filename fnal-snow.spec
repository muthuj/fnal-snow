Name:           fnal-snow
Summary:        Scripts and libraries to interact with Service Now @ FNAL
Version:        0
Release:        1%{?dist}
Packager:       Tim Skirvin <tskirvin@fnal.gov>
Group:          Applications/System
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Source0:        %{name}-%{version}-%{release}.tar.gz
BuildArch:      noarch

Requires:       perl perl-MIME-Lite perl-YAML
BuildRequires:  rsync
Vendor:         FNAL USCMS-T1
License:        BSD
Distribution:   CMS
URL:            http://www.fnal.gov/

%description
Installs scripts and tools that provide an interface to the Fermi Service
Now interface.

%prep

%setup -c -n %{name}-%{version}-%{release}

%build
%{__perl} perl/Makefile.PL
%{__make} PREFIX=%{_prefix}

%install
%%{__make} install PREFIX=$RPM_BUILD_ROOT%{_prefix}

rsync -Crlpt ./usr ${RPM_BUILD_ROOT}

mkdir -p ${RPM_BUILD_ROOT}/usr/share/man/man1
for i in `ls usr/bin`; do
    pod2man --section 1 --center="System Commands" usr/bin/${i} \
        > ${RPM_BUILD_ROOT}/usr/share/man/man1/${i}.1 ;
done

%clean
# Adding empty clean section per rpmlint.  In this particular case, there is 
# nothing to clean up as there is no build process

%files

%changelog
* Mon Jul 07 2014   Tim Skirvin <tskirvin@fnal.gov>   0-1
- initial packaging
