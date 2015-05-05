use ExtUtils::MakeMaker;

WriteMakefile(
    NAME           => 'FNAL-SNOW',
    DISTNAME       => 'FNAL-SNOW',
    FIRST_MAKEFILE => 'Makefile.perl',
    dist           => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    VERSION_FROM   => 'lib/FNAL/SNOW.pm',
    AUTHOR         => 'Tim Skirvin <tskirvin@fnal.edu>',
    PREREQ_PM      => {
        'ServiceNow' => '1.00',
    },
);
