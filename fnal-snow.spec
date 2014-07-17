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
# Empty build section added per rpmlint

%install
if [[ $RPM_BUILD_ROOT != "/" ]]; then
    rm -rf $RPM_BUILD_ROOT
fi

rsync -Crlpt ./usr ${RPM_BUILD_ROOT}

%clean
# Adding empty clean section per rpmlint.  In this particular case, there is 
# nothing to clean up as there is no build process

%files

%changelog
* Mon Jul 07 2014   Tim Skirvin <tskirvin@fnal.gov>   0-1
- initial packaging
