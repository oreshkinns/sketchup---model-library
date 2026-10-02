require 'csv'

module MafLibrary
  # CSV export for the model accounting report. UTF-8 BOM helps Excel detect Cyrillic.
  module ReportExport
    HEADERS = ['Название', 'Раздел', 'Тип', 'Статус распознавания', 'Статус дубля', 'Размещений',
               'Скрытых размещений', 'Скрытых тегов', 'Определений', 'ID каталога',
               'Версия каталога', 'Пути в модели', 'МАФ', 'Источник распознавания',
               'Объяснение распознавания', 'Область каталога'].freeze

    def self.recognition_label(model)
      if model['is_maf'] == true
        model['recognized_catalog'] ? 'МАФ из каталога' : 'Подтвержденная МАФ'
      elsif model['recognition_source'] == 'candidate'
        'Кандидат в МАФ'
      elsif model['recognition_reason'] == 'manual_rejected'
        'Отклонена'
      else
        'Другая модель'
      end
    end
    private_class_method :recognition_label

    def self.csv(report)
      rows = Array(report && report['models']).map do |model|
        [model['name'], model['category'], model['kind'],
         recognition_label(model),
         case model['duplicate_classification']
         when 'confirmed' then 'Подтвержденный дубль'
         when 'candidate', 'similar' then 'Кандидат'
         else 'Нет дублей'
         end,
         model['instances'], model['hidden_instances'], Array(model['hidden_tags']).join(' | '), model['definitions'],
         model['catalog_id'],
         model['catalog_version'], Array(model['paths']).join(' | '),
         model['is_maf'] == true ? 'Да' : 'Нет', model['recognition_source'],
         model['recognition_reason'], model['recognized_catalog_scope']]
      end
      "\xEF\xBB\xBF".force_encoding('UTF-8') +
        CSV.generate(row_sep: "\r\n") { |csv| csv << HEADERS; rows.each { |row| csv << row } }.encode('UTF-8')
    end
  end
end
