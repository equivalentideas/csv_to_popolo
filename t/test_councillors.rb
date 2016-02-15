require 'csv_to_popolo'
require 'minitest/autorun'
require 'json'

describe 'councillors' do
  subject     { Popolo::CSV.new('t/data/councillors.csv') }
  let(:organizations)  { subject.data[:organizations] }

  describe 'Patricia Gould' do
    let(:patricia) { subject.data[:persons][6] }
    let(:memberships) do
      subject.data[:memberships].select { |m| m[:person_id] == patricia[:id] }
    end

    it 'is associated with the correct council' do
      leg_mem = memberships.find { |m| m[:role] == 'member' }
      member_org = organizations.find { |o| o[:id] == leg_mem[:organization_id] }

      member_org[:name].must_equal 'Albury City Council'
    end
  end

  describe 'Albury City Council' do
    it 'has the correct classification' do
      albury_council = organizations[0]

      albury_council[:classification].must_equal 'legislature'
    end
  end
end
