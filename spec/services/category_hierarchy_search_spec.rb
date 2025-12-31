# frozen_string_literal: true

RSpec.describe CategoryHierarchySearch do
  before_all { SiteSetting.max_category_nesting = 3 }

  fab!(:parent_1) { Fabricate(:category, name: "Parent 1") }
  fab!(:parent_2) { Fabricate(:category, name: "Parent 2") }

  fab!(:parent_1_sub_category_1) do
    Fabricate(:category, name: "Parent 1 Sub Category 1", parent_category: parent_1)
  end

  fab!(:parent_1_sub_category_2) do
    Fabricate(:category, name: "Parent 1 Sub Category 2", parent_category: parent_1)
  end

  fab!(:parent_2_sub_category_1) do
    Fabricate(:category, name: "Parent 2 Sub Category 1", parent_category: parent_2)
  end

  fab!(:parent_2_sub_category_2) do
    Fabricate(:category, name: "Parent 2 Sub Category 2", parent_category: parent_2)
  end

  fab!(:parent_1_sub_category_1_sub_sub_category_1) do
    Fabricate(
      :category,
      name: "Parent 1 Sub Category 1 Sub Sub Category 1 Match",
      parent_category: parent_1_sub_category_1,
    )
  end

  fab!(:parent_1_sub_category_1_sub_sub_category_2) do
    Fabricate(
      :category,
      name: "Parent 1 Sub Category 1 Sub Sub Category 2",
      parent_category: parent_1_sub_category_1,
    )
  end

  fab!(:parent_1_sub_category_2_sub_sub_category_1) do
    Fabricate(
      :category,
      name: "Parent 1 Sub Category 2 Sub Sub Category 1",
      parent_category: parent_1_sub_category_2,
    )
  end

  fab!(:parent_1_sub_category_2_sub_sub_category_2) do
    Fabricate(
      :category,
      name: "Parent 1 Sub Category 2 Sub Sub Category 2",
      parent_category: parent_1_sub_category_2,
    )
  end

  fab!(:parent_2_sub_category_1_sub_sub_category_1) do
    Fabricate(
      :category,
      name: "Parent 2 Sub Category 1 Sub Sub Category 1",
      parent_category: parent_2_sub_category_1,
    )
  end

  fab!(:parent_2_sub_category_1_sub_sub_category_2) do
    Fabricate(
      :category,
      name: "Parent 2 Sub Category 1 Sub Sub Category 2",
      parent_category: parent_2_sub_category_1,
    )
  end

  fab!(:parent_2_sub_category_2_sub_sub_category_1) do
    Fabricate(
      :category,
      name: "Parent 2 Sub Category 2 Sub Sub Category 1",
      parent_category: parent_2_sub_category_2,
    )
  end

  fab!(:parent_2_sub_category_2_sub_sub_category_2) do
    Fabricate(
      :category,
      name: "Parent 2 Sub Category 2 Sub Sub Category 2 MATCH",
      parent_category: parent_2_sub_category_2,
    )
  end

  it "returns categories with their ancestors that match the terms param in hierarchy order" do
    context = described_class.call(params: { term: "match" })

    expect(context).to be_success

    expect(context.results).to eq(
      [
        parent_1,
        parent_1_sub_category_1,
        parent_1_sub_category_1_sub_sub_category_1,
        parent_2,
        parent_2_sub_category_2,
        parent_2_sub_category_2_sub_sub_category_2,
      ],
    )
  end

  it "returns categories with their ancestors that have ids that are included in the only_ids param in hierarchy order" do
    context =
      described_class.call(
        params: {
          only_ids: [
            parent_1_sub_category_1_sub_sub_category_1.id,
            parent_2_sub_category_2_sub_sub_category_2.id,
          ],
        },
      )

    expect(context).to be_success

    expect(context.results).to eq(
      [
        parent_1,
        parent_1_sub_category_1,
        parent_1_sub_category_1_sub_sub_category_1,
        parent_2,
        parent_2_sub_category_2,
        parent_2_sub_category_2_sub_sub_category_2,
      ],
    )
  end

  it "returns categories with their ancestors that have ids which is not included in the except_ids param in hierarchy order" do
    context =
      described_class.call(
        params: {
          except_ids: [
            parent_1_sub_category_2_sub_sub_category_1.id,
            parent_1_sub_category_2_sub_sub_category_2.id,
            parent_2_sub_category_1_sub_sub_category_1.id,
            parent_2_sub_category_1_sub_sub_category_2.id,
          ],
        },
      )

    expect(context).to be_success

    expect(context.results.map(&:name)).to eq(
      [
        parent_1.name,
        parent_1_sub_category_1.name,
        parent_1_sub_category_1_sub_sub_category_1.name,
        parent_1_sub_category_1_sub_sub_category_2.name,
        parent_1_sub_category_2.name,
        parent_2.name,
        parent_2_sub_category_1.name,
        parent_2_sub_category_2.name,
        parent_2_sub_category_2_sub_sub_category_1.name,
        parent_2_sub_category_2_sub_sub_category_2.name,
        "Uncategorized",
      ],
    )
  end
end
