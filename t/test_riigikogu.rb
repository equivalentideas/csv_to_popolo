#!/usr/bin/ruby

require 'csv_to_popolo'
require 'minitest/autorun'
require 'json'
require 'json-schema'

describe "riigikogu" do

  subject { 
    Popolo::CSV.from_file('t/data/riigikogu-members.csv')
  }

  let(:arto)  { subject.data[:persons].find { |i| i[:name] == 'Arto Aas' } }
  let(:mems)  { subject.data[:memberships].find_all   { |m| m[:person_id] == arto[:id] } }
  let(:orgs)  { subject.data[:organizations] }

  it "should have a record" do
    arto.class.must_equal Hash
  end

  it "should have the correct id" do
    arto[:id].must_equal 'fe748f4d-3f50-4af8-8069-92a460978d2b'
  end

  it "should have nested faction info" do
    mems.count.must_equal 2
    party_mem = mems.find { |m| m[:role] == 'party representative' }
    party = orgs.find { |o| party_mem[:organization_id] == o[:id] }
    party[:name].must_equal 'Eesti Reformierakonna fraktsioon'
    party[:classification].must_equal 'party'
  end

  it "should validate" do
    json = JSON.parse(subject.data.to_json)
    %w(person organization membership).each do |type|
      JSON::Validator.fully_validate("http://www.popoloproject.com/schemas/#{type}.json", json[type + 's'], :list => true).must_be :empty?
    end
  end
end

