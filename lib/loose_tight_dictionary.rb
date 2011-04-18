require 'active_support'
require 'active_support/version'
%w{
  active_support/core_ext/string
  active_support/core_ext/hash
  active_support/core_ext/object
}.each do |active_support_3_requirement|
  require active_support_3_requirement
end if ::ActiveSupport::VERSION::MAJOR == 3

# See the README for more information.
class LooseTightDictionary
  autoload :ExtractRegexp, 'loose_tight_dictionary/extract_regexp'
  autoload :Tightener, 'loose_tight_dictionary/tightener'
  autoload :Blocking, 'loose_tight_dictionary/blocking'
  autoload :Identity, 'loose_tight_dictionary/identity'
  autoload :Result, 'loose_tight_dictionary/result'
  autoload :Wrapper, 'loose_tight_dictionary/wrapper'
  autoload :Similarity, 'loose_tight_dictionary/similarity'
  autoload :Score, 'loose_tight_dictionary/score'
  
  class Freed < RuntimeError; end
  
  attr_reader :options
  attr_reader :haystack
  attr_reader :records

  # haystack - a bunch of records
  # options
  # * tighteners: regexps that essentialize strings down
  # * identities: regexps that rule out similarities, for example a 737 cannot be identical to a 747
  def initialize(records, options = {})
    @options = options.symbolize_keys
    @records = records
    @haystack = records.map { |record| Wrapper.new :parent => self, :record => record, :reader => haystack_reader }
  end
  
  def last_result
    @last_result ||= Result.new
  end
  
  def log(str = '') #:nodoc:
    (options[:log] || $stderr).puts str unless options[:log] == false
  end
    
  def find_all(needle, options = {})
    options = options.symbolize_keys.merge(:find_all => true)
    find needle, options
  end
  
  # todo fix record.record confusion (should be wrapper.record or smth)
  def find(needle, options = {})
    raise Freed if freed?
    free_last_result
    
    options = options.symbolize_keys
    gather_last_result = options.fetch(:gather_last_result, true)
    find_all = options.fetch(:find_all, false)
    
    if gather_last_result
      last_result.tighteners = tighteners
      last_result.identities = identities
      last_result.blockings = blockings
    end
    
    needle = Wrapper.new :parent => self, :record => needle
    
    if gather_last_result
      last_result.needle = needle
    end
    
    if strict_blocking and blockings.none? { |blocking| blocking.encompass? needle }
      if find_all
        return []
      else
        return nil
      end
    end

    encompassed, unencompassed = if strict_blocking and blockings.any?
      haystack.partition do |record|
        blockings.any? do |blocking|
          blocking.encompass?(needle, record) == true
        end
      end
    else
      [ haystack.dup, [] ]
    end
    
    if gather_last_result
      last_result.encompassed = encompassed
      last_result.unencompassed = unencompassed
    end
    
    possibly_identical, certainly_different = if identities.any?
      encompassed.partition do |record|
        identities.all? do |identity|
          answer = identity.identical? needle, record
          answer.nil? or answer == true
        end
      end
    else
      [ encompassed.dup, [] ]
    end
    
    if gather_last_result
      last_result.possibly_identical = possibly_identical
      last_result.certainly_different = certainly_different
    end
    
    if find_all
      return possibly_identical.map { |record| record.record }
    end
    
    similarities = possibly_identical.map do |record|
      needle.similarity record
    end.sort
    
    best_similarity = similarities[-1]
    record = best_similarity.wrapper2
    score = best_similarity.best_score.to_f
    
    if gather_last_result
      last_result.similarities = similarities
      last_result.record = record.record
      last_result.score = score
    end
    
    record.record
  end
  
  # Explain is like mysql's EXPLAIN command. You give it a needle and it tells you about how it was located (successfully or not) in the haystack.
  #
  #     d = LooseTightDictionary.new ['737', '747', '757' ]
  #     d.explain 'boeing 737-100'
  def explain(needle)
    record = find needle
    log "#" * 150
    log "# Match #{needle.inspect} => #{record.inspect}"
    log "#" * 150
    log
    log "Needle"
    log "-" * 150
    log last_result.needle.to_str
    log
    log "Haystack"
    log "-" * 150
    log last_result.haystack.map { |record| record.to_str }.join("\n")
    log
    log "Tighteners"
    log "-" * 150
    log last_result.tighteners.blank? ? '(none)' : last_result.tighteners.map { |tightener| tightener.inspect }.join("\n")
    log
    log "Blockings"
    log "-" * 150
    log last_result.blockings.blank? ? '(none)' : last_result.blockings.map { |blocking| blocking.inspect }.join("\n")
    log
    log "Identities"
    log "-" * 150
    log last_result.identities.blank? ? '(none)' : last_result.identities.map { |blocking| blocking.inspect }.join("\n")
    log
    log "Included"
    log "-" * 150
    log last_result.encompassed.blank? ? '(none)' : last_result.encompassed.map { |encompassed| encompassed.to_str }.join("\n")
    log
    log "Ignored"
    log "-" * 150
    log last_result.unencompassed.blank? ? '(none)' : last_result.unencompassed.map { |unencompassed| unencompassed.to_str }.join("\n")
    log
    log "Possibly identical"
    log "-" * 150
    log last_result.possibly_identical.blank? ? '(none)' : last_result.possibly_identical.map { |possibly_identical| possibly_identical.to_str }.join("\n")
    log
    log "Certainly different"
    log "-" * 150
    log last_result.certainly_different.blank? ? '(none)' : last_result.certainly_different.map { |certainly_different| certainly_different.to_str }.join("\n")
    log
    log "Similarities"
    log "-" * 150
    log last_result.similarities.blank? ? '(none)' : last_result.similarities.reverse[0..9].map { |similarity| similarity.inspect }.join("\n")
    log
    log "Match"
    log "-" * 150
    log record.inspect
  end
    
  def haystack_reader
    options[:haystack_reader]
  end
        
  def strict_blocking
    options[:strict_blocking] || false
  end

  def tighteners
    @tighteners ||= (options[:tighteners] || []).map do |regexp_or_str|
      Tightener.new regexp_or_str
    end
  end

  def identities
    @identities ||= (options[:identities] || []).map do |regexp_or_str|
      Identity.new regexp_or_str
    end
  end

  def blockings
    @blockings ||= (options[:blockings] || []).map do |regexp_or_str|
      Blocking.new regexp_or_str
    end
  end
  
  def freed?
    @freed == true
  end
  
  def free
    free_last_result
    @options.try :clear
    @options = nil
    @haystack.try :clear
    @haystack = nil
    @tighteners.try :clear
    @tighteners = nil
    @identities.try :clear
    @identities = nil
    @blockings.try :clear
    @blockings = nil
  ensure
    @freed = true
  end
  
  private
  
  def free_last_result
    @last_result.try :free
    @last_result = nil
  end
end
