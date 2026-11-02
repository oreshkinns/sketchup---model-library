import React from "react";
export function Sidebar() {
  return (
    <aside className={"sidebar"}>
      {"\r\n    "}
      <div className={"brand"}>
        <div className={"brand-mark"} aria-hidden={"true"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.6"}
            strokeLinejoin={"round"}
          >
            <path
              d={
                "m3 7 9-5 9 5v10l-9 5-9-5Z M3 7l9 5 9-5 M12 12v10 M7.5 4.5l9 5v5"
              }
            ></path>
          </svg>
        </div>
        <div>
          <strong>{"МАФ Каталог"}</strong>
          <small>{"БИБЛИОТЕКА МОДЕЛЕЙ"}</small>
        </div>
      </div>
      {"\r\n    "}
      <nav className={"nav"} aria-label={"Навигация"}>
        {"\r\n      "}
        <button className={"active"} data-page={"catalog"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <rect x={"3"} y={"3"} width={"7"} height={"7"} rx={"1"}></rect>
            <rect x={"14"} y={"3"} width={"7"} height={"7"} rx={"1"}></rect>
            <rect x={"3"} y={"14"} width={"7"} height={"7"} rx={"1"}></rect>
            <rect x={"14"} y={"14"} width={"7"} height={"7"} rx={"1"}></rect>
          </svg>
          {" Библиотека "}
          <span className={"num"} id={"nav-catalog"}>
            {"0"}
          </span>
        </button>
        {"\r\n      "}
        <button data-page={"overview"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <path d={"M4 20V10h4v10 M10 20V4h4v16 M16 20V7h4v13"}></path>
          </svg>
          {" Обзор"}
        </button>
        {"\r\n      "}
        <button data-page={"duplicates"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <rect x={"8"} y={"8"} width={"12"} height={"12"} rx={"2"}></rect>
            <path d={"M15 8V4H4v11h4"}></path>
          </svg>
          {" Дубли "}
          <span className={"num"} id={"nav-duplicates"}>
            {"0"}
          </span>
        </button>
        {"\r\n      "}
        <button data-page={"sections"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <path d={"M3 6h7l2 3h9v11H3Z"}></path>
          </svg>
          {" Разделы"}
        </button>
        {"\r\n      "}
        <button data-page={"cleanup"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <path d={"m14 3 3 3-7 9-4-4Z M6 11l-4 7 6 3 2-6 M15 20h7"}></path>
          </svg>
          {" Очистка"}
        </button>
        {"\r\n      "}
        <button data-page={"settings"}>
          <svg
            viewBox={"0 0 24 24"}
            fill={"none"}
            stroke={"currentColor"}
            strokeWidth={"1.7"}
            strokeLinejoin={"round"}
            strokeLinecap={"round"}
            aria-hidden={"true"}
          >
            <path d={"M4 7h16 M4 17h16"}></path>
            <circle cx={"9"} cy={"7"} r={"3"}></circle>
            <circle cx={"16"} cy={"17"} r={"3"}></circle>
          </svg>
          {" Настройки"}
        </button>
        {"\r\n    "}
      </nav>
      {"\r\n    "}
      <div className={"side-note"}>
        {"Личная · общая · облачная"}
        <br></br>
        {"SketchUp 2021–2026"}
      </div>
      {"\r\n  "}
    </aside>
  );
}

export function Header() {
  return (
    <header className={"top"}>
      <div>
        <div className={"eyebrow"} id={"mode-label"}>
          {"ОТКРЫТЫЙ ПРОЕКТ · ДЕМО"}
        </div>
        <h1 id={"page-title"}>{"Библиотека МАФ"}</h1>
      </div>
      <div className={"top-actions"}>
        <button className={"button"} id={"scan"}>
          {"Анализировать"}
        </button>
        <button className={"button danger"} id={"stop-scan"} hidden={true}>
          {"Остановить анализ"}
        </button>
        <details className={"command-menu add"} id={"catalog-add-menu"}>
          <summary>{"＋ Добавить"}</summary>
          <div className={"command-popover"}>
            <label>
              {"Библиотека"}
              <select
                className={"filter"}
                id={"import-scope"}
                aria-label={"Куда добавить модель"}
              >
                <option value={"personal"}>{"В личную"}</option>
                <option value={"shared"}>{"В общую локальную"}</option>
              </select>
            </label>
            <button className={"button"} id={"add-selected"}>
              {"Добавить выделенный в SketchUp"}
            </button>
            <button className={"button"} id={"import"}>
              {"Добавить файл .skp"}
            </button>
            <button className={"button"} id={"copy-selected"}>
              {"Создать копию выделенного…"}
            </button>
          </div>
        </details>
        <details className={"command-menu"} id={"project-tools"}>
          <summary aria-label={"Действия с проектом"}>{"⋯"}</summary>
          <div className={"command-popover"}>
            <button className={"button"} id={"replace-selected"}>
              {"Заменить выделенные"}
            </button>
            <button className={"button"} id={"theme-toggle"}>
              {"Сменить тему"}
            </button>
          </div>
        </details>
      </div>
    </header>
  );
}

export function OverviewPage() {
  return (
    <section className={"page"} id={"overview"}>
      {"\r\n      "}
      <div
        className={"row-actions"}
        style={{
          justifyContent: "flex-end",
          marginBottom: "10px",
        }}
      >
        <span className={"badge warn"} id={"report-stale"} hidden={true}>
          {"Отчет устарел · запустите анализ"}
        </span>
        <button className={"button small"} id={"export-report"}>
          {"Экспорт CSV"}
        </button>
      </div>
      {"\r\n      "}
      <div className={"metrics"}>
        <div className={"metric"}>
          <span>{"Все компоненты"}</span>
          <p id={"all-component-count"}></p>
          <span>{"включая вложенные"}</span>
        </div>
        <div className={"metric"}>
          <span>{"МАФ"}</span>
          <p id={"maf-count"}></p>
          <span>{"включая подтверждённые группы"}</span>
        </div>
        <div className={"metric"}>
          <span>{"Уникальных моделей"}</span>
          <b id={"m-unique"}>{"0"}</b>
          <span>{"с учётом дублей"}</span>
        </div>
        <div className={"metric warning"}>
          <span>{"Групп дублей"}</span>
          <b id={"m-duplicates"}>{"0"}</b>
          <span>{"требуют проверки"}</span>
        </div>
      </div>
      {"\r\n      "}
      <div
        className={"panel"}
        style={{
          marginBottom: "14px",
        }}
      >
        <div className={"panel-body"}>
          <strong>{"Учет модели"}</strong>
          <p className={"hint"} id={"accounting-summary"}>
            {
              "Запустите анализ для подсчета распознанных МАФ и неизвестных моделей."
            }
          </p>
          <div className={"hint"} id={"category-summary"}></div>
        </div>
      </div>
      {"\r\n      "}
      <div className={"content-grid"}>
        <div className={"panel"}>
          <div className={"panel-head"}>
            <div>
              <h2>{"Модели в проекте"}</h2>
              <p className={"hint"}>
                {
                  "Дерево — навигация по веткам. Действия с определением затрагивают все его размещения в проекте."
                }
              </p>
            </div>
            <label className={"maf-filter"}>
              <input type={"checkbox"} id={"maf-filter"}></input>
              {" Только МАФ"}
            </label>
            <select
              className={"filter"}
              id={"model-section"}
              aria-label={"Фильтр по разделу"}
            >
              <option value={""}>{"Все разделы"}</option>
            </select>
          </div>
          <div className={"selection-bar"} id={"selection-bar"} hidden={true}>
            <strong id={"selected-count"}>{"0 выбрано"}</strong>
            <button className={"button small"} id={"clear-selection"}>
              {"Снять выбор"}
            </button>
            <button className={"button small"} id={"selected-menu"}>
              {"Со всеми размещениями…"}
            </button>
          </div>
          <div className={"table-wrap"}>
            <table className={"table"}>
              <thead>
                <tr>
                  <th>{"Модель"}</th>
                  <th>{"Раздел"}</th>
                  <th>{"В ветке"}</th>
                  <th>{"Опред."}</th>
                  <th>{"Статус"}</th>
                </tr>
              </thead>
              <tbody id={"models-body"}></tbody>
            </table>
          </div>
        </div>
        <div className={"section-gap"}>
          <div className={"panel"}>
            <div className={"panel-head"}>
              <h2>{"Что требует внимания"}</h2>
            </div>
            <div className={"panel-body"}>
              <div className={"insight"}>
                <span className={"insight-mark"}>{"◇"}</span>
                <p className={"hint"} id={"insight"}></p>
              </div>
              <button className={"button small"} data-page={"duplicates"}>
                {"Открыть дубли →"}
              </button>
            </div>
          </div>
          <div className={"panel"}>
            <div className={"panel-head"}>
              <h2>{"Работа с проектом"}</h2>
            </div>
            <div className={"panel-body"}>
              <p className={"hint"}>
                {
                  "Контекстное меню позволяет сохранить компоненты в библиотеку, переименовать, назначить раздел, заменить или удалить размещения. Удаление и замена поддерживают Undo."
                }
              </p>
            </div>
          </div>
        </div>
      </div>
      {"\r\n      "}
      <div className={"panel candidate-panel"}>
        <div className={"panel-head"}>
          <div>
            <h2>{"Распознавание и параметры"}</h2>
            <p className={"hint"}>
              {
                "Кандидаты требуют решения. Подтверждение и отклонение применяются ко всем размещениям определения."
              }
            </p>
          </div>
        </div>
        <div id={"recognition-list"}></div>
      </div>
      {"\r\n    "}
    </section>
  );
}

export function DuplicatesPage() {
  return (
    <section className={"page"} id={"duplicates"}>
      <div className={"panel"}>
        <div className={"panel-head"}>
          <div>
            <h2>{"Повторяющиеся модели"}</h2>
            <p className={"hint"}>
              {"Сначала проверьте совпадение и область действия."}
            </p>
          </div>
          <button
            className={"button primary"}
            id={"focus-duplicates"}
            disabled={true}
          >
            {"Сфокусировать на выбранном"}
          </button>
        </div>
        <div
          className={"duplicate-scope-tabs"}
          role={"group"}
          aria-label={"Вид дублей"}
        >
          <button
            className={"button small"}
            data-duplicate-scope={"whole"}
            aria-pressed={"true"}
          >
            {"Целые МАФы "}
            <span id={"duplicate-whole-count"}>{"0"}</span>
          </button>
          <button
            className={"button small"}
            data-duplicate-scope={"other"}
            aria-pressed={"false"}
          >
            {"Другие модели проекта "}
            <span id={"duplicate-other-count"}>{"0"}</span>
          </button>
          <button
            className={"button small"}
            data-duplicate-scope={"nested"}
            aria-pressed={"false"}
          >
            {"Детали внутри МАФ "}
            <span id={"duplicate-nested-count"}>{"0"}</span>
          </button>
          <button
            className={"button small"}
            data-duplicate-scope={"placements"}
            aria-pressed={"false"}
          >
            {"Размещения"}
          </button>
          <button
            className={"button small"}
            data-duplicate-scope={"ignored"}
            aria-pressed={"false"}
          >
            {"Не дубли"}
          </button>
          <button className={"button small"} id={"reset-ignored"} hidden={true}>
            {"Сбросить исключения"}
          </button>
          <select
            className={"filter"}
            id={"duplicate-owner"}
            aria-label={"Выбрать родительский МАФ"}
            hidden={true}
          >
            <option value={""}>{"Все МАФы"}</option>
          </select>
          <button
            className={"button primary small"}
            id={"merge-nested"}
            hidden={true}
            disabled={true}
          >
            {"Объединить детали"}
          </button>
        </div>
        <div className={"duplicate-info"} id={"duplicate-scope-info"}></div>
        <div className={"duplicate-info"} id={"batch-toolbar"}>
          <strong id={"batch-count"}>{"Выбрано групп: 0"}</strong>{" "}
          <button
            className={"button small"}
            id={"batch-preview"}
            disabled={true}
          >
            {"Проверить пакет…"}
          </button>{" "}
          <button className={"button small"} id={"batch-reset"} disabled={true}>
            {"Сбросить пакет"}
          </button>
        </div>
        <div id={"duplicates-list"}></div>
      </div>
    </section>
  );
}

export function CatalogPage() {
  return (
    <section className={"page active"} id={"catalog"}>
      <div className={"section-gap"}>
        <div className={"panel catalog-shell"}>
          <div className={"catalog-toolbar"}>
            <label className={"catalog-search"}>
              <svg
                viewBox={"0 0 24 24"}
                fill={"none"}
                stroke={"currentColor"}
                strokeWidth={"1.7"}
                aria-hidden={"true"}
              >
                <circle cx={"10"} cy={"10"} r={"6"}></circle>
                <path d={"m15 15 5 5"}></path>
              </svg>
              <input
                className={"filter"}
                id={"search"}
                type={"search"}
                placeholder={"Найти модель или #тег"}
                aria-label={"Поиск моделей"}
              ></input>
            </label>
            <select
              className={"filter"}
              id={"category"}
              aria-label={"Фильтр по разделу"}
            >
              <option value={""}>{"Все разделы"}</option>
            </select>
            <select
              className={"filter"}
              id={"catalog-scope"}
              aria-label={"Источник библиотеки"}
            >
              <option value={""}>{"Все библиотеки"}</option>
              <option value={"personal"}>{"Личная"}</option>
              <option value={"shared"}>{"Общая локальная"}</option>
              <option value={"cloud"}>{"Общая онлайн"}</option>
            </select>
            <details className={"command-menu"} id={"catalog-tools"}>
              <summary aria-label={"Действия с библиотекой"}>{"⋯"}</summary>
              <div className={"command-popover"}>
                <label id={"compact-scope-label"}>
                  {"Показать"}
                  <select
                    className={"filter"}
                    id={"compact-catalog-scope"}
                    aria-label={"Источник библиотеки в меню"}
                  >
                    <option value={""}>{"Все библиотеки"}</option>
                    <option value={"personal"}>{"Личная"}</option>
                    <option value={"shared"}>{"Общая локальная"}</option>
                    <option value={"cloud"}>{"Общая онлайн"}</option>
                  </select>
                </label>
                <button className={"button"} data-choose-path={"shared"}>
                  {"Общая локальная: выбрать папку"}
                </button>
                <button className={"button"} id={"scan-catalog"}>
                  {"Проверить папку"}
                </button>
                <button className={"button"} id={"export-pack"}>
                  {"Экспорт видимых"}
                </button>
                <button className={"button"} id={"import-pack"}>
                  {"Импорт подборки"}
                </button>
              </div>
            </details>
          </div>
          <div className={"catalog-tabs"}>
            <button data-catalog-view={"all"} aria-pressed={"true"}>
              {"Все модели"}
            </button>
            <button data-catalog-view={"favorites"} aria-pressed={"false"}>
              {"Избранное"}
            </button>
            <button data-catalog-view={"recent"} aria-pressed={"false"}>
              {"Недавние"}
            </button>
            <select id={"catalog-view"} aria-label={"Подборка"}>
              <option value={"all"}>{"Все модели"}</option>
              <option value={"favorites"}>{"Избранное"}</option>
              <option value={"recent"}>{"Недавние"}</option>
            </select>
            <div
              className={"layout-controls"}
              role={"group"}
              aria-label={"Отображение библиотеки"}
            >
              <button data-catalog-layout={"small"} aria-pressed={"false"}>
                {"Мелкие"}
              </button>
              <button data-catalog-layout={"medium"} aria-pressed={"true"}>
                {"Средние"}
              </button>
              <button data-catalog-layout={"large"} aria-pressed={"false"}>
                {"Крупные"}
              </button>
              <button data-catalog-layout={"list"} aria-pressed={"false"}>
                {"Список"}
              </button>
            </div>
            <span
              className={"catalog-count"}
              id={"catalog-result-count"}
            ></span>
          </div>
          <div
            className={"shared-library-info"}
            id={"shared-library-info"}
            hidden={true}
          >
            <div>
              <strong>{"Общая локальная библиотека"}</strong>
              <p className={"hint"}>
                {"Модели можно добавлять. Удаление из плагина запрещено."}
              </p>
              <p className={"path"} id={"shared-library-path"}></p>
            </div>
            <button className={"button small"} data-choose-path={"shared"}>
              {"Выбрать папку"}
            </button>
          </div>
          <div id={"catalog-sync-errors"} hidden={true}></div>
          <div className={"catalog-list"} id={"catalog-list"}></div>
        </div>
        <details className={"catalog-help"}>
          <summary>{"Как работает библиотека"}</summary>
          <p>
            {
              "Личная библиотека хранит ваши модели. Общая локальная работает с папкой на компьютере или сетевом диске: её можно выбрать в меню библиотеки. Общая онлайн загружает модели по интернету. Удалять карточки через плагин можно только из личной библиотеки."
            }
          </p>
        </details>
      </div>
    </section>
  );
}

export function SectionsPage() {
  return (
    <section className={"page"} id={"sections"}>
      <div className={"panel"}>
        <div className={"panel-head"}>
          <div>
            <h2>{"Разделы МАФ"}</h2>
            <p className={"hint"}>
              {"Разделы объединяют модели проекта и библиотек"}
            </p>
          </div>
          <button className={"button primary"} id={"new-section"}>
            {"+ Новый раздел"}
          </button>
        </div>
        <div className={"list"} id={"sections-list"}></div>
      </div>
    </section>
  );
}

export function CleanupPage() {
  return (
    <section className={"page"} id={"cleanup"}>
      <div className={"section-gap"}>
        <div className={"panel"}>
          <div className={"panel-head"}>
            <div>
              <h2>{"Очистка модели"}</h2>
              <p className={"hint"}>
                {
                  "Выберите неиспользуемые определения для удаления. Действие можно отменить через Undo."
                }
              </p>
            </div>
            <button
              className={"button danger"}
              id={"cleanup-selected"}
              disabled={true}
            >
              {"Удалить выбранные…"}
            </button>
          </div>
          <div className={"panel-body"}>
            <p className={"hint cleanup-note"} id={"cleanup-info"}>
              {"Запустите анализ, чтобы увидеть неиспользуемые определения."}
            </p>
          </div>
          <div className={"list cleanup-list"} id={"cleanup-list"}></div>
          <div className={"panel-body cleanup-actions"}>
            <span className={"hint"}>
              {"Доступно для удаления: "}
              <b id={"unused-count"}>{"0"}</b>
            </span>
            <span className={"hint"}>
              {"Групп дублей: "}
              <b id={"cleanup-duplicates"}>{"0"}</b>
            </span>
            <button className={"button small"} data-page={"duplicates"}>
              {"Открыть дубли"}
            </button>
          </div>
        </div>
        <div className={"callout"}>
          {
            "Материалы, теги, изображения, вложенные и используемые определения не удаляются. После изменения модели повторите анализ."
          }
        </div>
      </div>
    </section>
  );
}

export function SettingsPage() {
  return (
    <section className={"page"} id={"settings"}>
      <div className={"section-gap"}>
        <div className={"panel"}>
          <div className={"panel-head"}>
            <div>
              <h2>{"Пути библиотек"}</h2>
              <p className={"hint"}>
                {"Пользовательские модели хранятся вне папки расширения"}
              </p>
            </div>
          </div>
          <div className={"setting-row"}>
            <h3>{"Личная библиотека"}</h3>
            <div className={"path"} id={"path-personal"}></div>
            <div className={"row-actions"}>
              <button className={"button small"} data-choose-path={"personal"}>
                {"Выбрать папку"}
              </button>
            </div>
          </div>
          <div className={"setting-row"}>
            <h3>{"Общая локальная библиотека"}</h3>
            <p className={"hint"}>
              {
                "Папка на этом компьютере или сетевом диске. Модели можно добавлять; удаление из плагина запрещено."
              }
            </p>
            <div className={"path"} id={"path-shared"}></div>
            <div className={"row-actions"}>
              <button className={"button small"} data-choose-path={"shared"}>
                {"Выбрать папку"}
              </button>
            </div>
          </div>
        </div>
        <div className={"panel"}>
          <div className={"panel-head"}>
            <div>
              <h2>{"Общая онлайн-библиотека"}</h2>
              <p className={"hint"}>
                {
                  "Публичный HTTPS-каталог JSON; модели скачиваются по запросу и проверяются по SHA-256"
                }
              </p>
            </div>
          </div>
          <div className={"panel-body section-gap"}>
            <div className={"field"}>
              <label htmlFor={"cloud-url"}>{"Адрес manifest.json"}</label>
              <input
                id={"cloud-url"}
                type={"url"}
                placeholder={"https://…/manifest.json"}
                spellcheck={"false"}
              ></input>
            </div>
            <div className={"row-actions"}>
              <button className={"button"} id={"save-cloud"}>
                {"Сохранить адрес"}
              </button>
              <button className={"button primary"} id={"sync-cloud"}>
                {"Синхронизировать"}
              </button>
            </div>
            <p className={"hint"}>
              {
                "Онлайн-каталог доступен только для чтения. Собственные модели добавляются в личную или общую локальную папку."
              }
            </p>
          </div>
        </div>
        <div className={"panel"}>
          <div className={"panel-head"}>
            <h2>{"Обновления плагина"}</h2>
          </div>
          <div className={"panel-body section-gap"}>
            <p className={"hint"} id={"update-message"}>
              {"Проверка обновлений GitHub Releases выполняется по кнопке."}
            </p>
            <div className={"row-actions"}>
              <button className={"button"} id={"check-update"}>
                {"Проверить обновления"}
              </button>
              <button
                className={"button primary"}
                id={"install-update"}
                hidden={true}
              >
                {"Установить обновление"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

export function ContextMenu() {
  return (
    <div
      className={"context-menu"}
      id={"context-menu"}
      role={"menu"}
      aria-label={"Действия с моделями"}
    >
      {"\r\n  "}
      <button role={"menuitem"} data-action={"add-library"}>
        {"Добавить в библиотеку"}
      </button>
      {"\r\n  "}
      <button role={"menuitem"} data-action={"rename"}>
        {"Переименовать"}
      </button>
      {"\r\n  "}
      <button role={"menuitem"} data-action={"section"}>
        {"Добавить в раздел"}
      </button>
      {"\r\n  "}
      <button role={"menuitem"} data-action={"replace"}>
        {"Заменить"}
      </button>
      {"\r\n  "}
      <button role={"menuitem"} data-action={"decision-confirmed"}>
        {"Подтвердить МАФ · все размещения"}
      </button>
      <button role={"menuitem"} data-action={"decision-rejected"}>
        {"Не МАФ · все размещения"}
      </button>
      <button role={"menuitem"} data-action={"decision-clear"}>
        {"Сбросить решение · все размещения"}
      </button>
      <div className={"rule"}></div>
      {"\r\n  "}
      <button role={"menuitem"} className={"danger"} data-action={"delete"}>
        {"Удалить из проекта"}
      </button>
      {"\r\n"}
    </div>
  );
}

export function ActionModal() {
  return (
    <div className={"modal-backdrop"} id={"modal-backdrop"}>
      <div
        className={"modal"}
        role={"dialog"}
        aria-modal={"true"}
        aria-labelledby={"modal-title"}
      >
        <div>
          <div className={"eyebrow"} id={"modal-eyebrow"}>
            {"ДЕЙСТВИЕ С МОДЕЛЯМИ"}
          </div>
          <h2 id={"modal-title"}></h2>
        </div>
        <div className={"modal-body"}>
          <p className={"hint"} id={"modal-description"}></p>
          <div className={"callout"} id={"action-scope"} hidden={true}></div>
          <div className={"field"} id={"modal-category-field"} hidden={true}>
            <label htmlFor={"modal-category"}>{"Раздел"}</label>
            <select id={"modal-category"}></select>
          </div>
          <div className={"field"} id={"modal-input-field"} hidden={true}>
            <label htmlFor={"modal-input"} id={"modal-input-label"}>
              {"Название"}
            </label>
            <input id={"modal-input"} type={"text"} maxLength={"80"}></input>
          </div>
          <div className={"field"} id={"modal-select-field"} hidden={true}>
            <label htmlFor={"modal-select"} id={"modal-select-label"}>
              {"Выберите вариант"}
            </label>
            <select id={"modal-select"}></select>
          </div>
          <div className={"callout"} id={"modal-summary"} hidden={true}></div>
          <label id={"manual-accept-field"} className={"callout"} hidden={true}>
            <input type={"checkbox"} id={"manual-accept"}></input>
            {
              " Я проверил эталон и принимаю замену геометрии, внутренних материалов, динамических параметров и свойств исходных определений содержимым эталона во всём проекте. Положения и атрибуты размещений сохраняются."
            }
          </label>
          <div
            className={"paste-zone"}
            id={"paste-zone"}
            contentEditable={"true"}
            role={"textbox"}
            aria-label={"Вставьте изображение из буфера"}
            hidden={true}
          ></div>
        </div>
        <div>
          <p
            id={"modal-status"}
            className={"modal-status"}
            role={"status"}
            hidden={true}
          ></p>
          <div className={"modal-actions"}>
            <button className={"button"} id={"cancel"}>
              {"Отмена"}
            </button>
            <button className={"button primary"} id={"confirm"}>
              {"Продолжить"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
export default function App() {
  return (
    <>
      {"\r\n"}
      <div className={"app"}>
        {"\r\n  "}
        <Sidebar />
        {"\r\n  "}
        <main className={"main"}>
          {"\r\n    "}
          <Header />
          {"\r\n    "}
          <div
            className={"callout"}
            id={"replacement-result"}
            role={"status"}
            aria-live={"polite"}
            hidden={true}
            style={{
              margin: "0 0 16px",
              flex: "none",
            }}
          >
            <strong id={"replacement-message"}></strong>
            <p className={"hint"}>
              {
                "Экземпляры используют выбранный эталон. При одинаковой геометрии внешний вид может не измениться. Отмена в SketchUp: Ctrl+Z."
              }
            </p>
            <span id={"replacement-refresh"}></span>
          </div>
          {"\r\n    "}
          <footer className={"app-footer"}>
            <div
              className={"status"}
              id={"status"}
              role={"status"}
              aria-live={"polite"}
            >
              {"Локальная библиотека"}
            </div>
            <span className={"analysis-time"} id={"analysis-time"}>
              {"Анализ ещё не запускался"}
            </span>
          </footer>
          {"\r\n\r\n    "}
          <OverviewPage />
          {"\r\n\r\n    "}
          <DuplicatesPage />
          {"\r\n\r\n    "}
          <CatalogPage />
          {"\r\n\r\n    "}
          <SectionsPage />
          {"\r\n\r\n    "}
          <CleanupPage />
          {"\r\n\r\n    "}
          <SettingsPage />
          {"\r\n  "}
        </main>
        {"\r\n"}
      </div>
      {"\r\n\r\n"}
      <ContextMenu />
      {"\r\n\r\n"}
      <ActionModal />
      {"\r\n"}
      <input
        id={"image-file"}
        type={"file"}
        accept={"image/png,image/jpeg,image/webp"}
        hidden={true}
      ></input>
      {"\r\n\r\n"}
    </>
  );
}
