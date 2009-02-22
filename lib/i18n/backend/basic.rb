module I18n
  module Backend

    ##
    # Methods that are *required* for an I18n backend as of 0.1.2.
    module PublicInterface
      def reload!
        raise "Must implement reload! for an I18n.backend"
      end

      def translate(locale, key, options = {})
        raise "Must implement translate for an I18n.backend"
      end

      def localize(locale, object, format = :default)
        raise "Must implement localize for an I18n.backend"
      end

      def store_translations(locale, data)
        raise "Must implement store_translations for an I18n.backend"
      end

      def available_locales
        raise "Must implement available_locales for an I18n.backend"
        # init_translations unless initialized?
        # translations.keys
      end
    end # PublicInterface

    ##
    # Methods that _should_ be implemented for an I18n backend.
    #
    # These are called by methods in the Basic module and used for testing.
    #
    # These are all included in the Basic module
    # so the simplest custom backend is:
    #  class CustomBackend
    #    include I18n::Backend::Basic
    #
    #    ... override methods ...
    #
    #  end
    #  I18n.backend = CustomBackend.new
    module BasicInterface

      protected

        def init_translations
          raise "Should implement init_translations for an I18n.backend"
        end

        def initialized?
          raise "Should implement initialized? for an I18n.backend"
        end

        def translations
          raise "Should implement translations for an I18n.backend"
        end

        def lookup(locale, key, scope = [])
          raise "Should implement lookup for an I18n.backend"
        end

    end # BasicInterface

    module Basic

      include PublicInterface, BasicInterface

      INTERPOLATION_RESERVED_KEYS = %w(scope default)
      MATCH = /(\\\\)?\{\{([^\}]+)\}\}/

      # Accepts a list of paths to translation files. Loads translations from
      # plain Ruby (*.rb) or YAML files (*.yml). See #load_rb and #load_yml
      # for details.
      def load_translations(*filenames)
        filenames.each { |filename| load_file(filename) }
      end

      # Stores translations for the given locale in memory.
      # This uses a deep merge for the translations hash, so existing
      # translations will be overwritten by new ones only at the deepest
      # level of the hash.
      def store_translations(locale, data)
        merge_translations(locale, data)
      end

      def translate(locales, key, options = {})
        raise I18n::InvalidLocale.new(locales) if locales.nil? || (Array === locales && locales.empty?)
        return key.map { |k| translate(locales, k, options) } if key.is_a? Array

        locales = Array(locales)
        reserved = :scope, :default
        count, scope, default = options.values_at(:count, *reserved)
        options.delete(:default)
        values = options.reject { |name, value| reserved.include?(name) }

        default, string_default = Array(default).select{|x| Symbol === x  }, Array(default).detect{|x| String === x  }

        entry = nil
        used_locale = nil

        ##
        # Lookup for each locale in locales
        # Assume that a locale specific default is better than a failover locale's translation
        Array(locales).each do | locale |
          entry = lookup(locale, key, scope)
          if entry.nil?
            entry = default(locale, default, options)
          end
          unless entry.nil?
            used_locale = locale
            break
          end
        end

        used_locale ||= locales.first

        # use the string_default
        entry = default(used_locale, string_default, options) if entry.nil?

        # raise if all failed
        raise(I18n::MissingTranslationData.new(used_locale, key, options)) if entry.nil?

        # process if not nil
        entry = pluralize(used_locale, entry, count)
        entry = interpolate(used_locale, entry, values)
        entry
      end

      # Acts the same as +strftime+, but returns a localized version of the
      # formatted date string. Takes a key from the date/time formats
      # translations as a format argument (<em>e.g.</em>, <tt>:short</tt> in <tt>:'date.formats'</tt>).
      def localize(locale, object, format = :default)
        raise ArgumentError, "Object must be a Date, DateTime or Time object. #{object.inspect} given." unless object.respond_to?(:strftime)

        type = object.respond_to?(:sec) ? 'time' : 'date'
        # TODO only translate these if format is a String?
        formats = translate(locale, :"#{type}.formats")
        format = formats[format.to_sym] if formats && formats[format.to_sym]
        # TODO raise exception unless format found?
        format = format.to_s.dup

        # TODO only translate these if the format string is actually present
        # TODO check which format strings are present, then bulk translate then, then replace them
        format.gsub!(/%a/, translate(locale, :"date.abbr_day_names")[object.wday])     if format.include?('%a')
        format.gsub!(/%A/, translate(locale, :"date.day_names")[object.wday])          if format.include?('%A')
        format.gsub!(/%b/, translate(locale, :"date.abbr_month_names")[object.mon])    if format.include?('%b')
        format.gsub!(/%B/, translate(locale, :"date.month_names")[object.mon])         if format.include?('%B')
        format.gsub!(/%p/, translate(locale, :"time.#{object.hour < 12 ? :am : :pm}")) if format.include?('%p') && object.respond_to?(:hour)
        object.strftime(format)
      end

      def initialized?
        @initialized ||= false
      end

      # Returns an array of locales for which translations are available
      def available_locales
        init_translations unless initialized?
        translations.keys
      end

      def reload!
        @initialized = false
        @translations = nil
      end

      protected
        def init_translations
          load_translations(*I18n.load_path.flatten)
          @initialized = true
        end

        def translations
          @translations ||= {}
        end

        # Looks up a translation from the translations hash. Returns nil if
        # eiher key is nil, or locale, scope or key do not exist as a key in the
        # nested translations hash. Splits keys or scopes containing dots
        # into multiple keys, i.e. <tt>currency.format</tt> is regarded the same as
        # <tt>%w(currency format)</tt>.
        def lookup(locale, key, scope = [])
          return unless key
          init_translations unless initialized?
          keys = I18n.send(:normalize_translation_keys, locale, key, scope)
          keys.inject(translations) do |result, k|
            if (x = result[k.to_sym]).nil?
              return nil
            else
              x
            end
          end
        end

        # Evaluates a default translation.
        # If the given default is a String it is used literally. If it is a Symbol
        # it will be translated with the given options. If it is an Array the first
        # translation yielded will be returned.
        #
        # <em>I.e.</em>, <tt>default(locale, [:foo, 'default'])</tt> will return +default+ if
        # <tt>translate(locale, :foo)</tt> does not yield a result.
        def default(locale, default, options = {})
          case default
            when String then default
            when Symbol then translate locale, default, options
            when Array  then default.each do |obj|
              result = default(locale, obj, options.dup) and return result
            end and nil
          end
        rescue I18n::MissingTranslationData
          nil
        end

        # Picks a translation from an array according to English pluralization
        # rules. It will pick the first translation if count is not equal to 1
        # and the second translation if it is equal to 1. Other backends can
        # implement more flexible or complex pluralization rules.
        def pluralize(locale, entry, count)
          return entry unless entry.is_a?(Hash) and count
          # raise InvalidPluralizationData.new(entry, count) unless entry.is_a?(Hash)
          key = :zero if count == 0 && entry.has_key?(:zero)
          key ||= count == 1 ? :one : :other
          raise I18n::InvalidPluralizationData.new(entry, count) unless entry.has_key?(key)
          entry[key]
        end

        # Interpolates values into a given string.
        #
        #   interpolate "file {{file}} opened by \\{{user}}", :file => 'test.txt', :user => 'Mr. X'
        #   # => "file test.txt opened by {{user}}"
        #
        # Note that you have to double escape the <tt>\\</tt> when you want to escape
        # the <tt>{{...}}</tt> key in a string (once for the string and once for the
        # interpolation).
        def interpolate(locale, string, values = {})
          return string unless string.is_a?(String)

          if string.respond_to?(:force_encoding)
            original_encoding = string.encoding
            string.force_encoding(Encoding::BINARY)
          end

          result = string.gsub(MATCH) do
            escaped, pattern, key = $1, $2, $2.to_sym

            if escaped
              pattern
            elsif INTERPOLATION_RESERVED_KEYS.include?(pattern)
              raise I18n::ReservedInterpolationKey.new(pattern, string)
            elsif !values.include?(key)
              raise I18n::MissingInterpolationArgument.new(pattern, string)
            else
              values[key].to_s
            end
          end

          result.force_encoding(original_encoding) if original_encoding
          result
        end

        # Loads a single translations file by delegating to #load_rb or
        # #load_yml depending on the file extension and directly merges the
        # data to the existing translations. Raises I18n::UnknownFileType
        # for all other file extensions.
        def load_file(filename)
          type = File.extname(filename).tr('.', '').downcase
          raise I18n::UnknownFileType.new(type, filename) unless respond_to?(:"load_#{type}")
          data = send :"load_#{type}", filename # TODO raise a meaningful exception if this does not yield a Hash
          data.each { |locale, d| merge_translations(locale, d) }
        end

        # Loads a plain Ruby translations file. eval'ing the file must yield
        # a Hash containing translation data with locales as toplevel keys.
        def load_rb(filename)
          eval(IO.read(filename), binding, filename)
        end

        # Loads a YAML translations file. The data must have locales as
        # toplevel keys.
        def load_yml(filename)
          YAML::load(IO.read(filename))
        end

        # Deep merges the given translations hash with the existing translations
        # for the given locale
        def merge_translations(locale, data)
          locale = locale.to_sym
          translations[locale] ||= {}
          data = deep_symbolize_keys(data)

          # deep_merge by Stefan Rusterholz, see http://www.ruby-forum.com/topic/142809
          merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
          translations[locale].merge!(data, &merger)
        end

        # Return a new hash with all keys and nested keys converted to symbols.
        def deep_symbolize_keys(hash)
          hash.inject({}) { |result, (key, value)|
            value = deep_symbolize_keys(value) if value.is_a? Hash
            result[(key.to_sym rescue key) || key] = value
            result
          }
        end
    end # Basic
  end # Backend
end # I18n
