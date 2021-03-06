require 'csv_to_popolo/version'
require 'csv'
require 'twitter_username_extractor'

class Popolo
  MODEL = {
    additional_name: {
      type: 'asis'
    },
    alternate_names: { 
      aliases: %w(other_names alternative_names)
    },
    area: {
      aliases: %w(constituency region district place)
    },
    area_id: {
      aliases: %w(constituency_id region_id district_id place_id)
    },
    biography: {
      aliases: %w(bio blurb),
      type: 'asis'
    },
    birth_date: {
      aliases: %w(dob date_of_birth),
      type: 'asis'
    },
    blog: {
      aliases: %w(weblog),
      type: 'link'
    },
    cell: {
      aliases: %w(mob mobile cellphone),
      type: 'contact'
    },
    chamber: {
      aliases: %w(house)
    },
    council: { },
    death_date: {
      aliases: %w(dod date_of_death),
      type: 'asis'
    },
    email: {
      type: 'asis'
    },
    end_date: {
      aliases: %w(end ended until to)
    },
    executive: {
      aliases: %w(post)
    },
    facebook: {
      type: 'link'
    },
    family_name: {
      aliases: %w(last_name surname lastname),
      type: 'asis'
    },
    fax: {
      aliases: %w(facsimile),
      type: 'contact'
    },
    flickr: {
      type: 'link'
    },
    gender: {
      aliases: %w(sex),
      type: 'asis'
    },
    given_name: {
      aliases: %w(first_name forename),
      type: 'asis'
    },
    group: {
      aliases: %w(party party_name faction faktion bloc block org organization organisation)
    },
    group_id: {
      # TODO: default
      aliases: %w(
        party_id faction_id faktion_id bloc_id block_id org_id
        organization_id organisation_id
      )
    },
    honorific_prefix: {
      type: 'asis'
    },
    honorific_suffix: {
      type: 'asis'
    },
    id: {
      # TODO: default
      type: 'asis'
    },
    image: {
      aliases: %w(img picture photo photograph portrait),
      type: 'asis'
    },
    instagram: {
      type: 'link'
    },
    linkedin: {
      type: 'link'
    },
    name: {
      type: 'asis',
      aliases: %w(name_en)
    },
    national_identity: {
      type: 'asis'
    },
    patronymic_name: {
      aliases: %w(patronym patronymic),
      type: 'asis'
    },
    phone: {
      aliases: %w(tel telephone),
      type: 'contact'
    },
    sort_name: {
      type: 'asis'
    },
    source: {
      aliases: %w(src)
    },
    start_date: {
      aliases: %w(start started from since)
    },
    summary: {
      type: 'asis'
    },
    term: {
      aliases: %w(legislative_period)
    },
    twitter: {
      type: 'contact'
    },
    website: {
      type: 'link',
      aliases: %w(homepage href url site)
    },
    wikipedia: {
      type: 'link'
    },
    youtube: {
      type: 'link'
    },

    other_name: {}
  }

  class CSV
    KEY_MAP = MODEL
              .select { |_, v| v.key? :aliases }
              .map { |k, v| v[:aliases].map { |iv| { iv => k } } }
              .flatten.reduce({}, :update)

    OPTS = {
      headers: true,
      header_converters: lambda do |h|
        # = HeaderConverters.symbol + remapping
        hc = h.to_s.encode(::CSV::ConverterEncoding).downcase.gsub(/\s+/, '_').gsub(/\W+/, '')
        (KEY_MAP[hc] || hc).to_sym
      end
    }

    def _idify(str)
      str.downcase.gsub(/\s+/, '_')
    end

    def initialize(file)
      @raw_csv = ::CSV.read(file, OPTS)
      @csv = @raw_csv.map do |r|
        r[:id] ||= "#{_idify(r[:name] || raise('creating ID without a name'))}"
        r[:group] = 'unknown' if r[:group].to_s.empty?
        r.to_hash.select { |_, v| !v.nil? }
      end
    end

    def data
      @data ||= {
        persons:       persons,
        organizations: organizations,
        memberships:   memberships,
        events:        terms,
        areas:         areas,
        warnings:      warnings
      }.select { |_, v| !v.nil? }
    end

    def find_person(p)
      if (@_people ||= {}).key? p[:id]
        # combine multiple person records additively. TODO: allow for multiple values
        existing = @_people[ p[:id] ]
        merged = p.merge(existing.to_hash)
        return @_people[ p[:id] ] = Person.new(merged)
      else
        return @_people[ p[:id] ] = Person.new(p)
      end
    end

    def persons
      @csv.map { |r| find_person(r) }.group_by { |r| r.to_hash[:id] }.map { |i, rs| rs.last.as_popolo }
    end

    def organizations
      if councils.any?
        councils + parties + chambers
      else
        parties + chambers + legislatures + executive
      end
    end

    def memberships
      if councils.any?
        council_memberships + council_executive_memberships
      else
        legislative_memberships + executive_memberships
      end
    end

    def areas
      @_areas ||= @csv.select { |r| (r.key?(:area) && !r[:area].to_s.empty?) || (r.key?(:area_id) && !r[:area_id].to_s.empty?) }.map { |r|
        { 
          id: r[:area_id].to_s.empty? ? "area/#{_idify(r[:area])}" : r[:area_id],
          name: r[:area] || 'unknown',
          type: 'constituency',
        }
      }.compact.uniq { |a| a[:id] }
    end

    def parties
      @_parties ||= @csv.select { |r| r.key? :group }.uniq { |r| r.key?(:group_id) ? r[:group_id] : r[:group] }.map do |r|
        {
          id: r[:group_id] || "party/#{_idify(r[:group])}",
          name: r[:group],
          classification: 'party'
        }
      end
    end

    def councils
      @_councils ||= @csv.select { |r| r.key? :council }.uniq { |r| r.key?(:council_id) ? r[:council_id] : r[:council] }.map do |r|
        {
          id: r[:council_id] || "legislature/#{_idify(r[:council])}",
          name: r[:council],
          classification: 'legislature'
        }
      end
    end

    def chambers
      # TODO: the chambers should be members of the Legislature
      @_chambers ||= @csv.select { |r| r.key? :chamber }.uniq { |r| r[:chamber] }.map do |r|
        {
          id: r[:chamber_id] || "chamber/#{_idify(r[:chamber])}",
          name: r[:chamber],
          classification: 'chamber'
        }
      end
    end

    def terms
      @_terms ||= @csv.select { |r| r.key? :term }.uniq { |r| r[:term] }.map do |r|
        {
          id: r[:term_id] || "term/#{_idify(r[:term])}",
          name: r[:term],
          classification: 'legislative period'
        }
      end
    end

    def legislatures
      legislative_memberships.count.zero? ? [] : [
        {
          id: 'legislature',
          name: 'Legislature',
          classification: 'legislature',
        }.select { |_, v| !v.nil? }
      ]
    end

    def executive
      executive_memberships.count.zero? ? [] : [{
        id: 'executive',
        name: 'Executive',
        classification: 'executive'
      }]
    end

    def legislative_memberships
      @_lmems ||= @csv.map do |r|
        mem = {
          person_id:          r[:id],
          organization_id:    find_chamber_id(r[:chamber]) || 'legislature',
          role:               'member',
          on_behalf_of_id:    r[:group_id] || find_party_id(r[:group]),
          area_id:            !r[:area_id].to_s.empty? ? r[:area_id] : !r[:area].to_s.empty? ? "area/#{_idify(r[:area])}" : nil,
          start_date:         r[:start_date],
          end_date:           r[:end_date]
        }.select { |_, v| !v.nil? }
        mem[:legislative_period_id] = "term/#{_idify(r[:term])}" if r.key? :term
        mem
      end
    end

    def council_memberships
      if councils.any?
        @csv.map do |r|
          mem = {
            person_id:          r[:id],
            organization_id:    find_council_id(r[:council]),
            role:               'councillor',
            on_behalf_of_id:    r[:group_id] || find_party_id(r[:group]),
            area_id:            !r[:area_id].to_s.empty? ? r[:area_id] : !r[:area].to_s.empty? ? "area/#{_idify(r[:area])}" : nil,
            start_date:         r[:start_date],
            end_date:           r[:end_date]
          }.select { |_, v| !v.nil? }
          mem[:legislative_period_id] = "term/#{_idify(r[:term])}" if r.key? :term
          mem
        end
      else
        []
      end
    end

    def council_executive_memberships
      @council_emems ||= @csv.select { |r| r.key?(:executive) && !r[:executive].to_s.empty? }.map do |r|
        mem = {
          person_id:          r[:id],
          organization_id:    find_council_id(r[:council]),
          role:               r[:executive]
        }
        mem[:legislative_period] = "term/#{_idify(r[:term])}" if r.key? :term
        mem
      end
    end

    def executive_memberships
      @_emems ||= @csv.select { |r| r.key?(:executive) && !r[:executive].to_s.empty? }.map do |r|
        mem = {
          person_id:          r[:id],
          organization_id:    'executive',
          role:               r[:executive]
        }
        mem[:legislative_period] = "term/#{_idify(r[:term])}" if r.key? :term
        mem
      end
    end

    def warnings
      handled = @raw_csv.headers.partition { |h| 
        MODEL.key?(h) || h.to_s.start_with?('identifier__') || h.to_s.start_with?('name__') 
        # || h.to_s.start_with?('wikipedia__')
      }

      # Ruby 2.1+ seems to return nil for empty headers; 2.0- returns ""
      blank = @raw_csv.headers.count    { |h| h.nil? || h.empty? }
      dupes = @raw_csv.headers.group_by { |h| h }.select { |_, hs| hs.size > 1 }

      warnings = {
        skipped: handled.last,
        dupes: dupes.map { |h, _| h }
      }.reject { |_, v| v.nil? || v.empty? }
      warnings[:blank] = blank unless blank.zero?
      warnings.empty? ? nil : warnings
    end

    private

    def find_party_id(name)
      (parties.find { |p| p[:name] == name } || return)[:id]
    end

    def find_council_id(name)
      (councils.find { |p| p[:name] == name } || return)[:id]
    end

    def find_chamber_id(name)
      (chambers.find { |p| p[:name] == name } || return)[:id]
    end
  end

  class Person
    def initialize(row)
      @r = row
    end

    def to_hash
      @r.to_hash
    end

    def given?(key)
      @r.key?(key) && !@r[key].nil? && !@r[key].empty?
    end

    def contact_details
      # Standardise Twitter handles
      if given? :twitter
        @r[:twitter] = TwitterUsernameExtractor.extract(@r[:twitter]) rescue nil
      end

      contacts = MODEL.select { |_, v| v[:type] == 'contact' }
                 .map    { |k, _| k }
                 .select { |type| given? type }
                 .map    { |type| { type: type.to_s, value: @r[type] } }
                 .compact
      contacts.count.zero? ? nil : contacts
    end

    def links
      links = (MODEL.select { |_, v| v[:type] == 'link' }
              .map    { |k, _| k }
              .select { |type| given? type }
              .map    { |type| { url: @r[type], note: type.to_s } } + wikipedia_links + twitter_link).compact
      links.count.zero? ? nil : links
    end

    def wikipedia_links
      @r.keys.find_all { |k| k.to_s.start_with? 'wikipedia__' }.map do |k|
        _, lang = k.to_s.split(/__/, 2)
        {
          url: 'https://%s.wikipedia.org/wiki/%s' % [lang, @r.delete(k).tr(' ','_')],
          note: "Wikipedia (#{lang})",
        }
      end
    end

    def twitter_link
      return [] unless given? :twitter
      [{
        url: 'https://twitter.com/' + @r[:twitter],
        note: 'twitter'
      }]
    end

    # Can't know up front what these might be; take anything in the form
    #   identifier__xxx
    def identifiers
      @r.keys.find_all { |k| k.to_s.start_with? 'identifier__' }.map do |k|
        {
          scheme: k.to_s.sub('identifier__', ''),
          identifier: @r.delete(k),
        }
      end
    end

    def per_language_names
      @r.keys.find_all { |k| k.to_s.start_with? 'name__' }.reject { |k| @r[k].to_s.empty? }.map do |k|
        {
          name: @r.delete(k),
          lang: k.to_s.sub('name__', '').tr('_','-'),
          note: "multilingual",
        }
      end
    end

    def alternate_names
      return [] unless given? :alternate_names
      @r[:alternate_names].split(/\s?;\s?/).map do |n|
        {
          name: n,
          note: "alternate",
        }
      end
    end

    def as_popolo
      popolo = {}
      as_is = MODEL.select { |_, v| v[:type] == 'asis' }.map { |k, _| k }
      as_is.each do |sym|
        popolo[sym] = @r[sym] if given? sym
      end

      popolo[:identifiers] = identifiers

      popolo[:other_names] = per_language_names + alternate_names
      popolo[:other_names] << { name: @r[:other_name] } if given?(:other_name)

      popolo[:contact_details] = contact_details
      popolo[:links] = links
      popolo[:images] = [{ url: @r[:image] }] if @r[:image]
      popolo[:sources] = [{ url: @r[:source] }] if given? :source

      popolo.reject { |_, v| v.nil? || v.empty? }
    end
  end
end
