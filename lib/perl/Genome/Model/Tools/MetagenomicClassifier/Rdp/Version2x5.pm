package Genome::Model::Tools::MetagenomicClassifier::Rdp::Version2x5;

use strict;
use warnings;

use Genome::InlineConfig;

class Genome::Model::Tools::MetagenomicClassifier::Rdp::Version2x5 {
    is => 'Genome::Model::Tools::MetagenomicClassifier::Rdp::ClassifierBase',
};

use Inline(
    Java => <<'END', 
      import edu.msu.cme.rdp.classifier.*;
      import edu.msu.cme.rdp.classifier.utils.*;

      class FactoryInstance {
         static ClassifierFactory f = null;

         public FactoryInstance(String property_path){
            ClassifierFactory.setDataProp(property_path, false);
            try {
                f = ClassifierFactory.getFactory();
            }
            catch (java.lang.Exception e) {
                e.printStackTrace(System.out);
            }
         }

         public Classifier createClassifier() {
            return f.createClassifier();
         }

         public String getHierarchyVersion() {
            return f.getHierarchyVersion();
         }

      };
END

    AUTOSTUDY => 1,
    CLASSPATH => join(':', map { $ENV{GENOME_SW_LEGACY_JAVA} . '/rdp-classifier/rdp-classifier-2.5/'.$_ } (qw/ rdp_classifier-2.5.jar ReadSeq.jar commons-cli.jar junit.jar /)),
    STUDY => [
        'edu.msu.cme.rdp.classifier.utils.ClassifierFactory',
        'edu.msu.cme.rdp.classifier.utils.ClassifierSequence',
        'edu.msu.cme.rdp.classifier.Classifier',
        'edu.msu.cme.rdp.classifier.ClassificationResult',
        'edu.msu.cme.rdp.classifier.RankAssignment',
    ],
    PACKAGE => 'main',
    DIRECTORY => Genome::InlineConfig::DIRECTORY(),
    EXTRA_JAVA_ARGS => '-Xmx2000m',
    JNI => 1,
);

sub create_classifier_sequence {
    return new edu::msu::cme::rdp::classifier::utils::ClassifierSequence($_[1]->{id}, '', $_[1]->{seq});
}

sub _is_reversed {
    my ($self, %params) = @_;
    return $params{classification_result}->getSequence()->isReverse();
}

1;

