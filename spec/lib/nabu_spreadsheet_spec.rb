require 'spec_helper'

describe Nabu::NabuSpreadsheet do
  let(:nabu_spreadsheet) { Nabu::NabuSpreadsheet.new }
  let(:data) { File.binread('spec/support/data/minimal_metadata/470 PDSC_minimal_metadataxls.xls') }
  # Because :collector_id is validated, rather than :collector, create has to be used.
  let(:user) { create(:user) }

  before do
    User.destroy_all
    # Ensure that NabuSpreadsheet doesn't complain that the collector does not exist.
    nabu_spreadsheet.stub(:user_from_str) { user }
    Essence.destroy_all
    Item.destroy_all
    Collection.destroy_all
    Country.create!(code: 'AD', name: 'Andorra') unless Country.find_by_code('AD')
    Country.create!(code: 'AF', name: 'Afghanistan') unless Country.find_by_code('AF')
    Language.create!(code: 'eng', name: 'English') unless Language.find_by_code('eng')
    Language.create!(code: 'deu', name: 'German') unless Language.find_by_code('deu')
    Language.create!(code: 'cmn', name: 'Mandarin') unless Language.find_by_code('cmn')
    Language.create!(code: 'yue', name: 'Cantonese') unless Language.find_by_code('yue')
  end

  describe '#load_spreadsheet' do
    context 'xls file provided' do
      it 'is valid' do
        nabu_spreadsheet.parse(data, nil)
        expect(nabu_spreadsheet).to be_valid
      end
    end

    context 'xlsx file provided' do
      let(:data) { File.binread('spec/support/data/minimal_metadata/470 PDSC_minimal_metadataxls.xlsx') }

      it 'is valid' do
        pending "Doesn't work in Ruby 1.9.3"
        nabu_spreadsheet.parse(data, nil)
        expect(nabu_spreadsheet).to be_valid
      end
    end

    context 'non-xls non-xlsx file provided' do
      let(:data) { 'Garbage content' }

      it 'is invalid' do
        nabu_spreadsheet.parse(data, nil)
        expect(nabu_spreadsheet).to_not be_valid
      end
    end
  end

  describe '#parse' do
    it 'determines collection identifier' do
      nabu_spreadsheet.parse(data, nil)
      collection = nabu_spreadsheet.collection
      # Note: Collection ID and Collector is the same in test data spreadsheet.
      expect(collection.identifier).to eq('VKS')
    end

    it 'determines collection title' do
      nabu_spreadsheet.parse(data, nil)
      collection = nabu_spreadsheet.collection
      expect(collection.title).to eq('Recording of Selako')
    end

    it 'determines collection description' do
      nabu_spreadsheet.parse(data, nil)
      collection = nabu_spreadsheet.collection
      expect(collection.description).to eq('Tribal history recounted by elders')
    end

    it 'determines item identifier' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      expect(item.identifier).to eq('107_79')
    end

    it 'determines item title' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      # Difference from identifier is this uses a dash, not an underscore
      expect(item.title).to eq('107-79')
    end

    it 'determines item description' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      expect(item.description).to eq('Nius blong Santo ribelion we Jimi Stevens i tekem ova Santo taon long May 28th 1980, ')
    end

    it 'can handle non-ASCII characters' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items[1]
      expect(item.description).to eq("Burlo, Ma\u00eb, ")
    end

    it 'can handle content language codes' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      content_language_codes = item.content_languages.map(&:code)
      expect(content_language_codes).to include('eng')
    end

    it 'can handle content language names' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      content_language_codes = item.content_languages.map(&:code)
      expect(content_language_codes).to include('deu')
    end

    it 'can handle subject language codes' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      subject_language_codes = item.subject_languages.map(&:code)
      expect(subject_language_codes).to include('cmn')
    end

    it 'can handle subject language names' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      subject_language_codes = item.subject_languages.map(&:code)
      expect(subject_language_codes).to include('yue')
    end

    it 'can handle countries' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      country_codes = item.countries.map(&:code)
      expect(country_codes).to eq(%w(AD AF))
    end

    it 'can handle origination date' do
      nabu_spreadsheet.parse(data, nil)
      item = nabu_spreadsheet.items.first
      expect(item.originated_on).to eq(Date.new(2015, 10, 26))
    end
  end

  describe '#user_from_str' do
    let(:first_name) { 'John' }
    let(:last_name) { 'Smith' }
    let(:user) { create(:user, first_name: first_name, last_name: last_name) }

    before do
      User.destroy_all
      nabu_spreadsheet.unstub(:user_from_str)
      user
    end

    context 'Comma separated' do
      let(:name) { 'John,Smith' }

      it 'Can find the user' do
        expect(nabu_spreadsheet.send(:user_from_str, name)).to eq(user)
      end
    end

    context 'Space within name' do
      let(:first_name) { 'John James' }
      let(:name) { 'John James,Smith' }

      it 'Can find the user' do
        expect(nabu_spreadsheet.send(:user_from_str, name)).to eq(user)
      end
    end

    context 'No last name, and whitespace exists after the comma' do
      let(:last_name) { nil }
      let(:name) { 'John, ' }

      it 'Can find the user' do
        expect(nabu_spreadsheet.send(:user_from_str, name)).to eq(user)
      end
    end

    context 'Has put the surname first' do
      let(:name) { 'Smith,John' }

      it 'Can find the user' do
        expect(nabu_spreadsheet.send(:user_from_str, name)).to eq(user)
      end
    end

    context 'Space separated' do
      let(:name) { 'John Smith' }

      it 'Can find the user' do
        expect(nabu_spreadsheet.send(:user_from_str, name)).to eq(user)
      end
    end
  end
end
