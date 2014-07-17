use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'FNAL-SNOW',
    DISTNAME      => 'FNAL-SNOW',
    dist          => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    VERSION_FROM  => 'lib/FNAL/SNOW.pm',
    AUTHOR        => 'Tim Skirvin <tskirvin@fnal.edu>',
    PREREQ_PM     => {
        'ServiceNow' => '1.08',
    },
);
