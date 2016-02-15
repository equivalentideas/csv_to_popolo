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
      leg_mem = memberships.find { |m| m[:role] == 'councillor' }
      member_org = organizations.find { |o| o[:id] == leg_mem[:organization_id] }

      member_org[:name].must_equal 'Albury City Council'
    end

    it 'only has one membership as they are a non-executive councillor' do
      assert memberships.count == 1
    end
  end

  describe 'Kevin Mack' do
    let(:kevin) { subject.data[:persons][0] }
    let(:memberships) do
      subject.data[:memberships].select { |m| m[:person_id] == kevin[:id] }
    end

    it 'has two memberships of their council' do
      number_of_memberships_for_albury_council = memberships.count do |m|
        m[:organization_id] == "legislature/albury_city_council"
      end

      assert number_of_memberships_for_albury_council == 2
    end

    it 'has the role of “Mayor”' do
      assert memberships.any? { |m| m[:role] == 'Mayor' }
    end
  end

  describe 'Albury City Council' do
    it 'has the correct classification' do
      albury_council = organizations[0]

      albury_council[:classification].must_equal 'legislature'
    end
  end

  it 'does not create a default legislature' do
    assert(organizations.none? { |org| org[:name] == "Legislature" },
           'There are no organizations with default name "Legislature"')
  end

  describe 'validation' do
    it 'does not say it has skipped the "council" column' do
      skipped_columns = subject.data[:warnings][:skipped]

      assert !skipped_columns.include?(:council)
    end
  end
end
