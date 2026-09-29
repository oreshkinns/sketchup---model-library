require 'minitest/autorun'
require_relative '../maf_library/report_export'

class ReportExportTest < Minitest::Test
  def test_csv_contains_accounting_columns_and_utf8_values
    report = {
      'models' => [{ 'name' => 'Скамья', 'category' => 'Парки', 'kind' => 'component',
                     'instances' => 3, 'definitions' => 1, 'catalog_id' => 'maf-1',
                     'hidden_instances' => 1, 'paths' => ['Парк / Скамья'],
                     'recognized_catalog' => true, 'catalog_version' => 2, 'status' => 'duplicate',
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
