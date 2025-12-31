# frozen_string_literal: true

class CategoryHierarchySearch
  include Service::Base

  params do
    attribute :term, :string
    attribute :only_ids, :array, default: [], compact_blank: true
    attribute :except_ids, :array, default: [], compact_blank: true

    after_validation do
      term = ActiveRecord::Base.connection.quote(term.strip.downcase) if term.present?
    end
  end

  step :execute_query

  private

  def execute_query(params:)
    query_params = { term: params.term }
    query_params[:only_ids] = params.only_ids if params.only_ids.present?
    query_params[:except_ids] = params.except_ids if params.except_ids.present?

    sql = <<~SQL
          WITH RECURSIVE
          matched AS (
            SELECT id
            FROM categories
            WHERE
              starts_with(LOWER(name), LOWER(:term))
              OR COALESCE(
                (
                  SELECT BOOL_AND(position(pattern IN LOWER(categories.name)) <> 0)
                  FROM unnest(regexp_split_to_array(LOWER(:term), '\\s+')) AS pattern
                ),
                true
              )
              #{params.only_ids.present? ? "AND categories.id IN (:only_ids)" : ""}
              #{params.except_ids.present? ? "AND categories.id NOT IN (:except_ids)" : ""}
          ),
          ancestors AS (
            SELECT c.id, c.parent_category_id
            FROM categories c
            JOIN matched m ON m.id = c.id

            UNION ALL

            SELECT p.id, p.parent_category_id
            FROM categories p
            JOIN ancestors a ON a.parent_category_id = p.id
          ),
          category_tree AS (
            SELECT
              c.id,
              c.parent_category_id,
              c.name,
              ARRAY[lower(c.name)]::text[] AS name_path,
              0 AS depth
            FROM categories c
            WHERE c.parent_category_id IS NULL

            UNION ALL

            SELECT
              c.id,
              c.parent_category_id,
              c.name,
              ct.name_path || lower(c.name),
              ct.depth + 1
            FROM categories c
            JOIN category_tree ct ON c.parent_category_id = ct.id
          )
          SELECT
            categories.*,
            ct.depth,
            ROW_NUMBER() OVER (ORDER BY ct.name_path, ct.id) AS position
          FROM category_tree ct
          JOIN categories ON categories.id = ct.id
          JOIN (SELECT DISTINCT id FROM ancestors) a ON a.id = ct.id
          ORDER BY ct.name_path, ct.id
        SQL

    context[:results] = Category.find_by_sql([sql, query_params])
  end
end
