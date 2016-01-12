require 'spec_helper'

describe ItemDestructionService do
  before do
    EssenceDestructionService.stub(:destroy).and_return({error: 'test fail'})

    #so there are no surprise directory deletions from the service tests
    FileUtils.stub(:rm_f).and_return nil
    FileUtils.stub(:rmdir).and_return nil
  end

  let(:item) {create(:item, content_languages: create_list(:language, 1), subject_languages: create_list(:language, 1))}

  context 'when item has no files' do
    let(:item_with_no_files) {create(:item, essences: [], content_languages: create_list(:language, 1), subject_languages: create_list(:language, 1))}
    it 'should proceed without errors when not deleting files' do
      response = ItemDestructionService.new(item_with_no_files, false).destroy
      expect(response[:success]).to eq(true)
      expect(response[:messages]).to have_key(:notice)
      expect(response[:messages]).to_not have_key(:error)
    end
    it 'should proceed without errors when attempting to delete files' do
      response = ItemDestructionService.new(item_with_no_files, true).destroy
      expect(response[:success]).to eq(true)
      expect(response[:messages]).to have_key(:notice)
      expect(response[:messages]).to_not have_key(:error)
    end
  end
  context 'when item has files' do
    let(:essence) {create(:sound_essence, item: item)}
    let(:item_with_files) {create(:item, essences: [essence], content_languages: create_list(:language, 1), subject_languages: create_list(:language, 1))}

    it 'should fail when attempting to leave files' do
      response = ItemDestructionService.new(item_with_files, false).destroy
      expect(response[:success]).to eq(false)
      expect(response[:messages]).to_not have_key(:notice)
      expect(response[:messages]).to have_key(:error)
      expect(response[:messages][:error]).to eq('Item has content files and cannot be removed.')
    end

    context 'when essence files are not present on the server' do
      it 'should proceed with errors when attempting to delete files' do
        response = ItemDestructionService.new(item_with_files, true).destroy
        expect(response[:success]).to eq(true)
        expect(response[:messages]).to have_key(:notice)
        expect(response[:messages]).to have_key(:error)
        expect(response[:messages][:notice]).to eq('Item and all its contents removed permanently (no undo possible)')
        expect(response[:messages][:error]).to start_with('Some errors occurred')
      end
    end

    context 'when essence files are present on the server' do
      before do
        EssenceDestructionService.stub(:destroy).and_return({notice: 'test success'})
      end
      it 'should proceed without errors when attempting to delete files' do
        response = ItemDestructionService.new(item_with_files, true).destroy
        expect(response[:success]).to eq(true)
        expect(response[:messages]).to have_key(:notice)
        expect(response[:messages]).to_not have_key(:error)
        expect(response[:messages][:notice]).to eq('Item and all its contents removed permanently (no undo possible)')
      end
    end
  end
end