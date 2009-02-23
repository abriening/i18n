$:.unshift "lib"

require 'rubygems'
require 'test/unit'
require 'mocha'
require 'i18n'
require 'active_support'

class I18nLocaleFallbackTest < Test::Unit::TestCase
  def setup
    I18n.backend = nil
    I18n.backend.store_translations :'en', {
      :currency => {
        :format => {
          :separator => '.',
          :delimiter => ',',
        }
      }
    }
  end

  def test_locale_can_be_an_array
    assert_nothing_raised{ I18n.locale = ['es-MX', 'es', 'en'] }
    assert_equal [:'es-MX', :es, :en], I18n.locale
  end

  def test_locale_fallback_if_missing_translation
    I18n.locale = ['es-MX', 'es', 'en']
    assert_raise(I18n::MissingTranslationData){ I18n.translate! :fallback, :locale => :en }

    fallback_en = "Fallback [en]"
    I18n.backend.store_translations :en, { :fallback => fallback_en }

    assert_equal fallback_en, I18n.translate( :fallback )

    fallback_es = "Fallback [es]"
    I18n.backend.store_translations :es, { :fallback => fallback_es }

    assert_equal fallback_es, I18n.translate( :fallback )

    fallback_es_mx = "Fallback [es-MX]"
    I18n.backend.store_translations :'es-MX', { :fallback => fallback_es_mx }

    assert_equal fallback_es_mx, I18n.translate( :fallback )

  end

  def test_string_default_not_used_when_fallback_symbol_default_exists
    I18n.locale = ['es-MX', 'es', 'en']

    fallback_en = "Fallback [en]"
    I18n.backend.store_translations :en, { :fallback => fallback_en }

    assert_equal fallback_en, I18n.translate(:missing_key, :default => [:fallback, "String"])

  end


  # TODO 2009-02-22
  # move the tests below elsewhere
  # they have nothing to do with fallback locales
  # testing the Hash default
  def test_hash_default
    I18n.locale = :en

    assert_equal "Hash Default [en]", I18n.translate(:missing_key, :default => {:es => "Hash predeterminado [es]", :en => "Hash Default [en]"} )

  end

  def test_hash_default_in_default_array
    I18n.locale = :en

    assert_equal "Hash Default [en]", I18n.translate(:missing_key, :default => [:missing_again, {:es => "Hash predeterminado [es]", :en => "Hash Default [en]"}] )

  end

  def test_hash_default_with_array_value
    I18n.locale = :en

    assert_equal "Hash Default [en]", I18n.translate(:missing_key, :default => {:es => "Hash predeterminado [es]", :en => [ :missing_en, "Hash Default [en]"] } )


    missing_text = "Missing [en]"
    I18n.backend.store_translations :en, { :missing_en => missing_text }

    assert_equal "Missing [en]", I18n.translate(:missing_key, :default => {:es => "Hash predeterminado [es]", :en => [ :missing_en, "Hash Default [en]"] } )

  end

end
