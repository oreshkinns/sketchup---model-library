require 'minitest/autorun'
require_relative '../maf_library/report_export'

class ReportExportTest < Minitest::Test
  def test_csv_contains_accounting_columns_and_utf8_values
    report = {
      'models' => [{ 'name' => 'Скамья', 'category' => 'Парки', 'kind' => 'component',
                     'instances' => 3, 'definitions' => 1, 'catalog_id' => 'maf-1',
                     'hidden_instances' => 1, 'paths' => ['Парк / Скамья'],
                     'is_maf' => true, 'recognized_catalog' => true, 'catalog_version' => 2, 'status' => 'duplicate',
                     'duplicate_classification' => 'candidate' }],
      'summary' => { 'instances' => 3 }
    }
    csv = MafLibrary::ReportExport.csv(report)
    assert_includes csv, "Название,Раздел,Тип,Статус распознавания,Статус дубля,Размещений,Скрытых размещений"
    assert_includes csv, 'Кандидат'
    assert_includes csv, 'Скамья'
    assert_includes csv, 'Парк / Скамья'
    assert_includes csv, 'maf-1'
    assert_includes csv, 'МАФ из каталога'
    assert_includes csv.b, "\xEF\xBB\xBF".b
  end
end

class ReportExportTest
  def test_csv_uses_confirmed_classification_and_includes_source_and_reason
    report = {'models' => [
      {'name' => 'Окно', 'kind' => 'component', 'instances' => 2, 'definitions' => 1,
       'is_maf' => false, 'recognized_catalog' => true, 'recognition_source' => 'other',
       'recognition_reason' => 'architectural_exclusion', 'catalog_id' => 'legacy'},
      {'name' => 'Скамья', 'kind' => 'component', 'instances' => 3, 'definitions' => 1,
       'is_maf' => true, 'recognized_catalog' => false, 'recognition_source' => 'manual',
       'recognition_reason' => 'manual_confirmed'},
      {'name' => 'Component#1', 'kind' => 'component', 'instances' => 1, 'definitions' => 1,
       'is_maf' => false, 'recognition_source' => 'candidate', 'recognition_reason' => 'unknown_type'}]}
    csv = MafLibrary::ReportExport.csv(report).delete_prefix("\xEF\xBB\xBF")
    rows = CSV.parse(csv, headers: true)
    refute_equal 'МАФ из каталога', rows[0]['Статус распознавания']
    assert_equal 'Нет', rows[0]['МАФ']
    assert_equal 'Да', rows[1]['МАФ']
    assert_equal 'Нет', rows[2]['МАФ']
    assert_equal 'manual', rows[1]['Источник распознавания']
    assert_equal 'manual_confirmed', rows[1]['Объяснение распознавания']
    assert_equal 'architectural_exclusion', rows[0]['Объяснение распознавания']
    assert_equal 'Кандидат в МАФ', rows[2]['Статус распознавания']
    assert_equal '3', rows[1]['Размещений']
  end
end
