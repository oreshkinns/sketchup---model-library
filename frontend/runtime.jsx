import { indexCatalogLinks } from "./catalogLinks.cjs";
import { DuplicateCard } from "./components.jsx";
import {
  DuplicateActions,
  ModelTreeRow,
  RecognitionCard,
  CatalogCard,
  SectionRow,
  PlacementGroup,
  CleanupRow,
} from "./components.jsx";
import React from "react";
import { mountView, viewList } from "./viewHost.jsx";
export function initializeRuntime() {
  const $ = (id) => document.getElementById(id);
  const previewJobs = new Map();
  const demo = !window.sketchup;
  const clone = (value) => JSON.parse(JSON.stringify(value));
  // SketchUp 2021.0 embeds CEF 64: no optional chaining, ?? or Array.flatMap.
  const valueOr = (value, fallback) => (value == null ? fallback : value);
  const flattenMap = (items, callback) =>
    items.reduce(
      (result, item, index) => result.concat(callback(item, index)),
      [],
    );
  const sample = {
    summary: {
      instances: 47,
      unique: 4,
      definitions: 6,
      duplicate_groups: 2,
    },
    models: [
      {
        id: "catalog:bench",
        definition_ids: ["101", "102"],
        name: "Скамья Линия 1800",
        category: "Скамейки",
        instances: 18,
        definitions: 2,
        status: "duplicate",
      },
      {
        id: "catalog:bin",
        definition_ids: ["103", "104"],
        name: "Урна Порт",
        category: "Урны",
        instances: 11,
        definitions: 2,
        status: "duplicate",
      },
      {
        id: "definition:105",
        definition_ids: ["105"],
        name: "Опора Свет 4 м",
        category: "Светильники",
        instances: 12,
        definitions: 1,
        status: "ok",
      },
      {
        id: "definition:106",
        definition_ids: ["106"],
        name: "Качели Дуэт",
        category: "Площадки",
        instances: 6,
        definitions: 1,
        status: "ok",
      },
    ],
    definitions: [
      {
        id: "101",
        name: "Скамья Линия 1800",
        instances: 12,
      },
      {
        id: "102",
        name: "Скамья Линия 1800#1",
        instances: 6,
      },
      {
        id: "103",
        name: "Урна Порт",
        instances: 8,
      },
      {
        id: "104",
        name: "Урна Порт (копия)",
        instances: 3,
      },
      {
        id: "105",
        name: "Опора Свет 4 м",
        instances: 12,
      },
      {
        id: "106",
        name: "Качели Дуэт",
        instances: 6,
      },
    ],
    duplicates: [
      {
        id: "bench",
        label: "Скамья Линия 1800",
        confidence: "Каталог · одинаковый ID",
        definitions: [
          {
            id: "101",
            name: "Скамья Линия 1800",
            instances: 12,
          },
          {
            id: "102",
            name: "Скамья Линия 1800#1",
            instances: 6,
          },
        ],
      },
      {
        id: "bin",
        label: "Урна Порт",
        confidence: "Похожая геометрия · проверить вручную",
        definitions: [
          {
            id: "103",
            name: "Урна Порт",
            instances: 8,
          },
          {
            id: "104",
            name: "Урна Порт (копия)",
            instances: 3,
          },
        ],
      },
    ],
    catalog: [
      {
        id: "a",
        name: "Скамья Линия 1800",
        category: "Скамейки",
        scope: "personal",
      },
      {
        id: "b",
        name: "Урна Порт",
        category: "Урны",
        scope: "shared",
      },
      {
        id: "c",
        name: "Опора Свет 4 м",
        category: "Светильники",
        scope: "cloud",
      },
      {
        id: "d",
        name: "Качели Дуэт",
        category: "Площадки",
        scope: "personal",
      },
    ],
    sections: ["Скамейки", "Урны", "Светильники", "Площадки", "Другое"],
    settings: {
      personal: "~/MAF Library",
      shared: "~/MAF Shared Library",
      cloud_url:
        "https://raw.githubusercontent.com/oreshkinns/sketchup---model-library/main/cloud-library/manifest.json",
    },
    cleanup: {
      unused_definitions: 7,
    },
  };
  sample.models.forEach((row, index) =>
    Object.assign(row, {
      kind: "component",
      is_maf: index !== 2,
      recognition_source: index === 2 ? "candidate" : "manual",
      recognition_reason: index === 2 ? "component_flags" : "manual_confirmed",
      paths: ["Двор / " + row.name, "Парк / " + row.name],
      metadata: {
        bbox_mm: [1800, 500, 900],
        faces_count: 120,
        edges_count: 240,
        materials_count: 2,
        nesting_depth: 1,
        behavior_flags: {
          dynamic: index === 2,
        },
      },
    }),
  );
  sample.summary = {
    ...sample.summary,
    all_component_instances: 47,
    all_component_definitions: 6,
    maf_instances: 35,
    maf_definitions: 5,
  };
  sample.hierarchy = [
    {
      id: "yard",
      definition_id: "yard",
      row_id: null,
      name: "Двор",
      kind: "group",
      instances: 2,
      is_maf: false,
      has_maf_descendant: true,
      children: sample.models.map((row, i) => ({
        id: "yard/" + i,
        definition_id: row.definition_ids[0],
        row_id: row.id,
        name: row.name,
        kind: "component",
        instances: row.instances,
        is_maf: row.is_maf,
        children: [],
      })),
    },
  ];
  sample.catalog.forEach((card, index) =>
    Object.assign(card, {
      project_placements: [18, 11, 0, 6][index],
      version: 1,
      bbox_mm: [1800, 500, 900],
      faces_count: 120,
      edges_count: 240,
      materials_count: 2,
      file_size_bytes: 220000,
      recognition_source: "manual",
      sha256: "a".repeat(64),
    }),
  );
  sample.models.forEach((row, index) => {
    if (row.is_maf)
      Object.assign(row, {
        recognized_catalog: true,
        catalog_id: sample.catalog[index].id,
        recognized_catalog_scope: sample.catalog[index].scope,
      });
  });
  let activePage = "catalog",
    pageOffsets = {};
  const pageSize = 100;
  const pageTargets = {
    models: "models-body",
    recognition: "recognition-list",
    catalog: "catalog-list",
    duplicates: "duplicates-list",
  };
  function pageItems(kind, items) {
    const target = $(pageTargets[kind]);
    let pager = $("pager-" + kind);
    if (!pager) {
      pager = document.createElement("div");
      pager.id = "pager-" + kind;
      pager.className = "row-actions";
      pager.style.padding = "12px";
      (kind === "models" ? target.closest(".table-wrap") : target).after(pager);
    }
    const limit = kind === "duplicates" ? 10 : pageSize;
    const last = Math.max(0, Math.ceil(items.length / limit) - 1);
    const page = Math.min(pageOffsets[kind] || 0, last);
    pageOffsets[kind] = page;
    pager.hidden = items.length <= limit;
    mountView(
      pager,
      <>
        <button
          className={"button small"}
          data-page-prev={kind}
          {...(page === 0
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Назад"}
        </button>
        <span className={"hint"}>
          {items.length ? page * limit + 1 : 0}
          {"–"}
          {Math.min((page + 1) * limit, items.length)}
          {" из "}
          {items.length}
        </span>
        <button
          className={"button small"}
          data-page-next={kind}
          {...(page === last
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Далее"}
        </button>
      </>,
    );
    return items.slice(page * limit, (page + 1) * limit);
  }
  function clearInactivePages() {
    for (const [kind, id] of Object.entries(pageTargets)) {
      const page =
        kind === "models" || kind === "recognition" ? "overview" : kind;
      if (page === activePage) continue;
      const target = $(id);
      if (target.firstChild) mountView(target, null);
      const pager = $("pager-" + kind);
      if (pager) pager.hidden = true;
    }
  }
  let collapsedNodes = new Set(),
    selectedNodeIds = new Set(),
    versionTarget = null,
    selectedUpdateTarget = null,
    selectedUpdateRequest = 0,
    catalogDeleteTarget = null,
    catalogSectionTarget = null,
    sectionDeleteTarget = null,
    cleanupTarget = [],
    actionInvalidated = false,
    modalIds = Object.freeze([]);
  let state = demo
    ? clone(sample)
    : {
        summary: {
          instances: 0,
          unique: 0,
          definitions: 0,
          duplicate_groups: 0,
        },
        models: [],
        definitions: [],
        duplicates: [],
        catalog: [],
        sections: [],
        settings: {},
        cleanup: {},
      };
  let manualPreviewToken = "",
    manualPreviewReady = false;
  const batchSelection = new Map(),
    batchTargets = new Map();
  let batchSnapshot = "",
    batchServerToken = "",
    batchReady = false;
  function batchRequests() {
    return Array.from(batchSelection.values()).map((x) => ({
      group_id: x.group_id,
      target_id: x.target_id,
    }));
  }
  function invalidateBatch() {
    batchSnapshot = "";
    batchServerToken = "";
    batchReady = false;
    if (modalKind === "batch-manual") {
      actionInvalidated = true;
      $("confirm").disabled = true;
      $("manual-accept").checked = false;
    }
  }
  function resetBatch() {
    batchSelection.clear();
    batchTargets.clear();
    invalidateBatch();
  }
  function renderBatchToolbar() {
    $("batch-count").textContent = "Выбрано групп: " + batchSelection.size;
    $("batch-preview").disabled = !!state.report_stale || !batchSelection.size;
    $("batch-reset").disabled = !batchSelection.size;
  }
  function batchControls(group) {
    const key = String(group.id),
      selected = batchSelection.get(key),
      target = selected
        ? selected.target_id
        : batchTargets.get(key) ||
          String((group.definitions[0] || {}).id || ""),
      unsupported =
        duplicateScope === "ignored" || group.definitions.length < 2;
    let defs = visibleDefinitions(group).slice();
    if (!defs.some((d) => String(d.id) === target)) {
      const chosen = group.definitions.find((d) => String(d.id) === target);
      if (chosen) defs = [chosen, ...defs.slice(0, 19)];
    }
    return (
      <DuplicateActions
        defs={defs}
        group={group}
        groupKey={key}
        selected={selected}
        state={state}
        target={target}
        unsupported={unsupported}
        viewList={viewList}
      />
    );
  }
  function requestBatchPreview() {
    $("modal-status").hidden = false;
    $("modal-status").textContent =
      "Применение недоступно: ожидается проверка всех групп.";
    invalidateBatch();
    actionInvalidated = false;
    batchSnapshot = JSON.stringify(batchRequests());
    const token = String(++previewToken);
    $("modal-summary").hidden = false;
    $("modal-summary").textContent = "Проверяем все группы и размещения…";
    if (
      !send(
        "preview_batch_manual_replace_duplicates",
        JSON.stringify(batchRequests()),
        token,
      )
    )
      $("modal-summary").textContent = "Предпросмотр доступен в SketchUp.";
  }
  function previewPaths(container, paths, label = "Пути") {
    if (!paths.length) return;
    const details = document.createElement("details"),
      title = document.createElement("summary"),
      list = document.createElement("ul"),
      more = document.createElement("button");
    details.className = "preview-details";
    title.textContent = label + " · " + paths.length;
    more.className = "button";
    more.type = "button";
    let shown = 0;
    function next() {
      paths.slice(shown, shown + 20).forEach((path) => {
        const li = document.createElement("li");
        li.textContent = path;
        list.appendChild(li);
      });
      shown = Math.min(shown + 20, paths.length);
      more.textContent = "Показать ещё · осталось " + (paths.length - shown);
      more.hidden = shown >= paths.length;
    }
    details.addEventListener("toggle", () => {
      if (details.open && !shown) next();
    });
    more.addEventListener("click", next);
    details.append(title, list, more);
    container.appendChild(details);
  }
  function previewIssues(container, items, label) {
    if (!items.length) return;
    const groups = new Map();
    items.forEach((item) => {
      const x =
          typeof item === "string"
            ? {
                reason: item,
              }
            : item,
        key = [x.name || "", x.reason || x.message || "Требует проверки"].join(
          ": ",
        );
      if (!groups.has(key))
        groups.set(key, {
          count: 0,
          paths: [],
        });
      const group = groups.get(key);
      group.count++;
      group.paths.push(...(x.paths || []));
    });
    const heading = document.createElement("p");
    heading.textContent = label + ": " + items.length;
    container.appendChild(heading);
    groups.forEach((group, key) => {
      const row = document.createElement("div");
      row.className = "preview-blocker";
      row.textContent = key.replace(/^: /, "") + " · " + group.count;
      previewPaths(row, Array.from(new Set(group.paths)));
      container.appendChild(row);
    });
  }
  function renderBatchPreview(payload) {
    if (
      modalKind !== "batch-manual" ||
      actionInvalidated ||
      String(payload.token) !== String(previewToken) ||
      batchSnapshot !== JSON.stringify(batchRequests())
    )
      return;
    const plan = payload.plan || {},
      blockers = plan.blockers || [],
      groups = plan.groups || [];
    batchServerToken = payload.preview_token || "";
    batchReady =
      !payload.error &&
      !!batchServerToken &&
      plan.entities > 0 &&
      !blockers.length &&
      !groups.some((g) => ((g.plan || {}).blockers || []).length);
    const summary = $("modal-summary");
    summary.style.whiteSpace = "normal";
    summary.textContent = payload.error
      ? "Предпросмотр недоступен: " + payload.error
      : "Весь проект · групп: " +
        groups.length +
        "; экземпляров: " +
        (plan.entities || 0) +
        "; размещений: " +
        (plan.placements || 0);
    groups.forEach((g) => {
      const p = g.plan || {},
        row = document.createElement("div");
      row.textContent = `${g.group_id}: ${(p.sources || []).join(", ")} → ${p.target || g.target_id}; экземпляров: ${p.entities || 0}; размещений: ${p.placements || 0}`;
      if (p.warning) {
        const warning = document.createElement("p");
        warning.textContent = p.warning;
        row.appendChild(warning);
      }
      previewIssues(row, p.blockers || [], "Блокировки");
      previewIssues(row, p.warnings || [], "Предупреждения");
      previewPaths(row, p.paths || []);
      summary.appendChild(row);
    });
    previewIssues(summary, blockers, "Блокировки");
    const warning = document.createElement("p");
    warning.textContent =
      plan.warning ||
      "Геометрия, внутренние материалы, динамические параметры и свойства всех исходных определений заменятся эталонами во всём проекте. Положения и атрибуты размещений сохранятся. Весь пакет отменяется одним Undo.";
    summary.appendChild(warning);
    updateManualConfirmation();
  }
  let nestedMergeOwner = "",
    nestedMergeToken = "",
    selectedIds = new Set(),
    anchorId = null,
    modalKind = "",
    modalTrigger = null,
    contextTrigger = null,
    duplicateGroup = null,
    imageTarget = null,
    pendingUpdate = null;
  let pairSelections = new Map();
  let placementRequest = 0,
    placementData = null,
    placementDefinition = "";
  let definitionPages = new Map(),
    metadataSource = null,
    metadataMap = new Map();
  let summarySource = null,
    summaryKnown = [],
    summaryUnknown = [];
  let treeCache = null;
  const focusGroups = new Map();
  function focusGroupKey(group) {
    const key = String(focusGroups.size);
    focusGroups.set(key, group);
    return key;
  }
  function definitionKey(group) {
    return JSON.stringify([
      duplicateScope,
      group.owner_id || "",
      group.id,
      group.definitions.slice(0, 2).map((d) => d.id),
    ]);
  }
  function visibleDefinitions(group) {
    const key = definitionKey(group),
      page = Math.min(
        definitionPages.get(key) || 0,
        Math.max(0, Math.ceil(group.definitions.length / 20) - 1),
      );
    return group.definitions.slice(page * 20, page * 20 + 20);
  }
  function definitionMetadata(id) {
    if (metadataSource !== state.models) {
      metadataSource = state.models;
      metadataMap = new Map();
      (state.models || []).forEach((row) =>
        (row.definition_ids || []).forEach((id) =>
          metadataMap.set(String(id), row.metadata || {}),
        ),
      );
    }
    return metadataMap.get(String(id)) || {};
  }
  let cleanupSelection = new Set(),
    duplicatePreviews = new Map(),
    previewEpoch = 0,
    duplicateScope = "whole",
    catalogLayout = "medium";
  try {
    const saved = localStorage.getItem("maf.catalog.layout");
    if (["small", "medium", "large", "list"].includes(saved))
      catalogLayout = saved;
  } catch (error) {}
  let duplicateSelection = new Set(),
    scanStartedAt = null,
    scanTimer = null,
    scanState = "idle",
    demoScanTimer = null,
    previewToken = 0;
  function status(message, type = "") {
    $("status").textContent = message;
    $("status").className = "status " + type;
  }
  function renderReplacementResult() {
    const box = $("replacement-result");
    if (box.hidden) return;
    $("replacement-refresh").textContent =
      scanState === "running" || scanState === "stopping"
        ? "Обновляем список дублей… Действия станут доступны после анализа."
        : state.report_stale
          ? "Список ещё не обновлён. Нажмите «Анализировать», чтобы продолжить."
          : "Список дублей обновлён. Можно продолжать работу.";
  }
  function duration(seconds) {
    return `${Math.max(0, seconds).toFixed(2)} с`;
  }
  function setScanState(next, seconds, force = false) {
    if (next === "running") {
      if (scanState === "stopping" && !force) return;
      if (scanState === "idle") {
        scanStartedAt = performance.now();
        if (scanTimer) clearInterval(scanTimer);
        scanTimer = setInterval(
          () =>
            ($("analysis-time").textContent =
              `${scanState === "stopping" ? "Остановка" : "Анализ"}: ${duration((performance.now() - scanStartedAt) / 1000)}`),
          100,
        );
      }
      scanState = "running";
      $("scan").disabled = true;
      $("stop-scan").hidden = false;
      $("stop-scan").disabled = false;
      $("stop-scan").textContent = "Остановить анализ";
      $("analysis-time").textContent = "Анализ: 0.00 с";
      return;
    }
    if (next === "stopping") {
      scanState = "stopping";
      $("scan").disabled = true;
      $("stop-scan").hidden = false;
      $("stop-scan").disabled = true;
      $("stop-scan").textContent = "Останавливается…";
      status("Запрошена остановка анализа. Ожидаем остановки…");
      return;
    }
    if (next !== "idle") return;
    const wasStopping = scanState === "stopping",
      wasRunning = scanState === "running";
    scanState = "idle";
    if (scanTimer) clearInterval(scanTimer);
    scanTimer = null;
    scanStartedAt = null;
    $("scan").disabled = false;
    $("stop-scan").hidden = true;
    $("stop-scan").disabled = false;
    $("stop-scan").textContent = "Остановить анализ";
    if (seconds != null)
      $("analysis-time").textContent =
        `Анализ выполнен за ${duration(seconds)}`;
    else if (wasStopping) {
      $("analysis-time").textContent = "Анализ остановлен";
      status("Анализ остановлен.");
    } else if (wasRunning) $("analysis-time").textContent = "Анализ прерван";
  }
  function send(action, ...args) {
    if (
      !demo &&
      window.sketchup &&
      typeof window.sketchup[action] === "function"
    ) {
      window.sketchup[action](...args);
      return true;
    }
    return false;
  }
  function scopeName(scope) {
    return (
      {
        personal: "Личная",
        shared: "Общая локальная",
        cloud: "Общая онлайн",
      }[scope] || scope
    );
  }
  function visibleModels() {
    const section = $("model-section").value;
    return (state.models || []).filter(
      (row) => !section || row.category === section,
    );
  }
  function renderSelectOptions() {
    for (const id of ["model-section", "category"]) {
      const select = $(id),
        old = select.value;
      mountView(select, [
        <option value={""}>{"Все разделы"}</option>,
        viewList(
          (state.sections || []).map((s) => <option value={s}>{s}</option>),
        ),
      ]);
      select.value = (state.sections || []).includes(old) ? old : "";
    }
  }
  function renderSelection() {
    document
      .querySelectorAll(".model-row")
      .forEach((row) =>
        row.setAttribute(
          "aria-selected",
          String(
            selectedIds.has(row.dataset.row) &&
              (!selectedNodeIds.size || selectedNodeIds.has(row.dataset.node)),
          ),
        ),
      );
    $("selection-bar").hidden = selectedIds.size === 0;
    $("selected-count").textContent = `Выбрано моделей: ${selectedIds.size}`;
  }
  function sourceLabel(source) {
    return (
      {
        manual: "Подтверждено пользователем",
        rule: "Локальные правила",
        catalog: "Связь с каталогом",
        exact_match: "Полный точный отпечаток",
        candidate: "Кандидат",
        other: "Другая модель",
      }[source] ||
      source ||
      "—"
    );
  }
  function reasonLabel(reason) {
    return (
      {
        manual_confirmed: "Подтверждено вручную",
        manual_rejected: "Отклонено вручную",
        local_profile:
          "Имя, габариты и геометрия соответствуют локальному профилю",
        complete_fingerprint_match: "Полный отпечаток совпадает",
        confirmed_catalog_link: "Подтверждённая связь с карточкой",
        component_flags: "Особенности компонента требуют проверки",
        incomplete_geometry: "Неполная или выборочная геометрия",
        invalid_dimensions: "Некорректные габариты",
        missing_faces: "Нет граней",
        unknown_axes: "Оси неизвестны",
        ambiguous_type: "Несколько возможных типов",
        blank_name: "Нет названия",
        unknown_type: "Тип не определён",
        dimensions_outside_profile: "Габариты вне профиля",
        architectural_exclusion: "Архитектурный объект",
        structural_group: "Группа-контейнер",
      }[reason] ||
      reason ||
      "—"
    );
  }
  function warningLabel(warning) {
    return (
      {
        catalog_match_ambiguous:
          "Несколько точных карточек: связь не выбрана; размещения не отнесены к карточке. Для отдельной карточки выделите один компонент в SketchUp и используйте «Создать копию выделенного» в библиотеке",
        catalog_geometry_drift: "Геометрия отличается от сохранённой версии",
        catalog_geometry_unverified:
          "Полный отпечаток сохранённой версии недоступен",
        catalog_instance_variant:
          "Сохранена масштабная копия выделенного экземпляра; число размещений этой карточки не определено",
        legacy_card_unconfirmed: "Сохранённая карточка не подтверждена",
      }[warning] || warning
    );
  }
  function geometryText(meta) {
    return `${valueOr(meta.faces_count, "—")} граней · ${valueOr(meta.edges_count, "—")} рёбер · ${valueOr(meta.materials_count, "—")} материалов`;
  }
  function dimensions(meta) {
    return Array.isArray(meta.bbox_mm) && meta.bbox_mm.length
      ? meta.bbox_mm.map((v) => Math.round(v)).join(" × ") + " мм"
      : "—";
  }
  function renderModels() {
    if (activePage !== "overview") return;
    const rows = new Map((state.models || []).map((row) => [row.id, row]));
    const section = $("model-section").value,
      mafOnly = $("maf-filter").checked;
    const accepts = (node) => {
      const row = rows.get(node.row_id);
      return (
        (!mafOnly || node.is_maf === true) &&
        (!section || (row && row.category) === section)
      );
    };
    const visibility = new Map();
    const visible = (node) => {
      if (!visibility.has(node))
        visibility.set(
          node,
          accepts(node) || (node.children || []).some(visible),
        );
      return visibility.get(node);
    };
    const nodes =
      state.hierarchy ||
      (state.models || []).map((row) => ({
        id: row.id,
        row_id: row.id,
        name: row.name,
        kind: row.kind,
        is_maf: row.is_maf,
        instances: row.instances,
        children: [],
      }));
    const renderNode = (node, depth) => {
      if (!visible(node)) return "";
      const row = rows.get(node.row_id),
        children = (node.children || []).filter(visible),
        open = !collapsedNodes.has(node.id),
        actionable = !!row;
      const identity = node.is_maf
        ? "МАФ · " + sourceLabel(row && row.recognition_source)
        : node.kind === "group"
          ? "Контейнер"
          : (row && row.recognition_source) === "candidate"
            ? "Кандидат"
            : "Другая модель";
      return (
        <ModelTreeRow
          actionable={actionable}
          children={children}
          depth={depth}
          identity={identity}
          node={node}
          open={open}
          row={row}
          valueOr={valueOr}
          key={node.id}
        />
      );
    };
    let visibleNodes = [];
    const collect = (items, depth) => {
      for (const node of items) {
        if (!visible(node)) continue;
        visibleNodes.push({
          node,
          depth,
        });
        if (!collapsedNodes.has(node.id))
          collect(node.children || [], depth + 1);
      }
    };
    const cacheKey = [
      state.models,
      state.hierarchy,
      section,
      mafOnly,
      Array.from(collapsedNodes).join("\u0000"),
    ];
    if (
      treeCache &&
      cacheKey.every((value, index) => value === treeCache.key[index])
    )
      visibleNodes = treeCache.nodes;
    else {
      collect(nodes, 0);
      treeCache = {
        key: cacheKey,
        nodes: visibleNodes,
      };
    }
    mountView(
      $("models-body"),
      viewList(
        pageItems("models", visibleNodes).map(({ node, depth }) =>
          renderNode(node, depth),
        ),
      ) || (
        <tr>
          <td colSpan={"5"} className={"empty"}>
            {"Модели не найдены. Запустите анализ или измените фильтр."}
          </td>
        </tr>
      ),
    );
    renderSelection();
  }
  function renderRecognition() {
    if (activePage !== "overview") return;
    mountView(
      $("recognition-list"),
      viewList(
        pageItems("recognition", state.models || []).map((row) => {
          const m = row.metadata || {},
            candidate = row.recognition_source === "candidate" && !row.is_maf;
          return (
            <RecognitionCard
              candidate={candidate}
              dimensions={dimensions}
              geometryText={geometryText}
              m={m}
              reasonLabel={reasonLabel}
              row={row}
              sourceLabel={sourceLabel}
              state={state}
              valueOr={valueOr}
              viewList={viewList}
              warningLabel={warningLabel}
              key={row.id}
            />
          );
        }),
      ) || <p className={"empty"}>{"Параметры появятся после анализа."}</p>,
    );
  }
  let syncWarningsPending = false;
  let syncWarningsSignature = "";
  let syncWarningsAnalyzing = false;
  let syncWarningReturnFocus = null;
  function closeSyncWarnings() {
    const dialog = $("sync-warning-dialog");
    if (dialog && dialog.open) dialog.close();
    const target = syncWarningReturnFocus;
    if (target && target.isConnected && target.offsetParent !== null) target.focus();
    else $("show-sync-warnings")?.focus();
  }
  function openSyncWarnings() {
    const dialog = $("sync-warning-dialog");
    if (!dialog || dialog.open || $("modal-backdrop").classList.contains("open")) return;
    syncWarningReturnFocus = document.activeElement;
    syncWarningsPending = false;
    dialog.showModal();
    $("close-sync-warnings").focus();
  }
  function renderSyncErrors() {
    const errors = state.catalog_sync_errors || [];
    const signature = JSON.stringify(errors.map(error => [error.row_id, error.message, error.code, ((state.models || []).find(row => row.id === error.row_id) || {}).name]));
    if (signature === syncWarningsSignature && $("sync-warning-dialog")) {
      if (syncWarningsPending) openSyncWarnings();
      return;
    }
    syncWarningsSignature = signature;
    const existing = $("sync-warning-dialog");
    if (existing?.open) existing.close();
    $("catalog-sync-errors").hidden = !errors.length;
    mountView($("catalog-sync-errors"), errors.length ? <>
      <button className="button small" id="show-sync-warnings" onClick={openSyncWarnings}>Показать предупреждения ({errors.length})</button>
      <dialog id="sync-warning-dialog" className="sync-warning-dialog" onKeyDown={(event) => {
          if (event.key !== "Tab") return;
          const nodes = Array.from(event.currentTarget.querySelectorAll("button, summary")).filter(node => node.offsetParent !== null);
          const first = nodes[0], last = nodes[nodes.length - 1];
          if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
          if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        }} aria-labelledby="sync-warning-title" onCancel={(event) => { event.preventDefault(); closeSyncWarnings(); }}>
        <header className="sync-warning-header"><div><div className="eyebrow">Личная библиотека · {errors.length}</div><h2 id="sync-warning-title">Не удалось сохранить модели</h2></div><button className="button" id="close-sync-warnings" aria-label="Закрыть предупреждения" onClick={closeSyncWarnings}>×</button></header>
        <p className="hint">Модели остались в проекте. Проверьте причины и повторите анализ.</p>
        <ul className="sync-warning-list">{errors.map((error, index) => <li key={index}><details><summary><span className="sync-warning-marker" aria-hidden="true">!</span><span>{((state.models || []).find(row => row.id === error.row_id) || {}).name || "Модель"}</span><span className="sync-warning-chevron" aria-hidden="true">⌄</span></summary><p>{error.message || error.code || "Неизвестная причина"}</p></details></li>)}</ul>
        <footer><button className="button primary" id="retry-catalog-sync">Повторить анализ</button></footer>
      </dialog>
    </> : null);
    if (syncWarningsPending && errors.length) openSyncWarnings();
  }
  function renderCatalog() {
    if (activePage !== "catalog") return;
    const query = $("search")
        .value.trim()
        .toLowerCase()
        .split(/\s+/)
        .filter(Boolean),
      category = $("category").value,
      scope = $("catalog-scope").value,
      view = $("catalog-view").value;
    $("shared-library-info").hidden = scope !== "shared";
    $("shared-library-path").textContent =
      (state.settings || {}).shared ||
      "Выберите папку на компьютере или сетевом диске.";
    document
      .querySelectorAll("[data-catalog-view]")
      .forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          button.dataset.catalogView === view ? "true" : "false",
        ),
      );
    const linkedByScope = indexCatalogLinks(state.models || []);
    let items = (state.catalog || []).filter((x) => {
      const tags = Array.isArray(x.tags) ? x.tags : [];
      const searchable = [x.name, x.category, ...tags].join(" ").toLowerCase();
      return (
        query.every((word) =>
          word.startsWith("#")
            ? tags.some((tag) => tag.toLowerCase().includes(word.slice(1)))
            : searchable.includes(word),
        ) &&
        (!category || x.category === category) &&
        (!scope || x.scope === scope) &&
        (view !== "favorites" || x.favorite) &&
        (view !== "recent" || x.last_used_at)
      );
    });
    if (view === "recent")
      items.sort((a, b) =>
        String(b.last_used_at).localeCompare(String(a.last_used_at)),
      );
    $("catalog-result-count").textContent = items.length + " моделей";
    $("catalog-list").dataset.layout = catalogLayout;
    document
      .querySelectorAll("[data-catalog-layout]")
      .forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.catalogLayout === catalogLayout),
        ),
      );
    mountView(
      $("catalog-list"),
      items.length
        ? viewList(
            pageItems("catalog", items).map((x) => {
              const tags = Array.isArray(x.tags) ? x.tags : [];
              const bbox = dimensions(x);
              const size =
                x.file_size_bytes != null
                  ? `${x.file_size_bytes} байт`
                  : "Размер файла: —";
              const complexity = geometryText(x);
              const meta = [bbox, size, complexity].filter(Boolean).join(" · ");
              const linkedIds = linkedByScope.get(x.scope);
              const linked = (linkedIds && linkedIds.get(x.id)) || [];
              const warnings = Array.from(
                new Set([
                  ...(x.recognition_warnings || []),
                  ...flattenMap(
                    linked,
                    (row) => row.recognition_warnings || [],
                  ),
                ]),
              );
              const count =
                state.report_stale || x.project_placements == null
                  ? "—"
                  : `${x.project_placements} размещений`;
              return (
                <CatalogCard
                  count={count}
                  linked={linked}
                  meta={meta}
                  scopeName={scopeName}
                  sourceLabel={sourceLabel}
                  tags={tags}
                  valueOr={valueOr}
                  warningLabel={warningLabel}
                  warnings={warnings}
                  x={{...x, previewJob: previewJobs.get(`${x.scope}:${x.id}`)}}
                  key={x.scope + ":" + x.id}
                />
              );
            }),
          )
        : (pageItems("catalog", items),
          (
            <div className={"empty"}>
              {"В выбранной библиотеке моделей пока нет."}
            </div>
          )),
    );
  }
  function renderReportStaleOnly() {
    $("report-stale").hidden = !state.report_stale;
    renderRecognition();
    renderCatalog();
  }
  function duplicateItems() {
    const items =
      duplicateScope === "ignored"
        ? state.ignored_duplicates || []
        : duplicateScope === "placements"
          ? state.placement_groups || []
          : duplicateScope === "other"
            ? state.other_duplicates || []
            : duplicateScope === "nested"
              ? state.nested_duplicates || []
              : state.duplicates || [];
    const owner = $("duplicate-owner").value;
    return duplicateScope === "nested" && owner
      ? items.filter((group) => group.owner_id === owner)
      : items;
  }
  function renderDuplicateControls() {
    renderBatchToolbar();
    $("reset-ignored").hidden = duplicateScope !== "ignored";
    $("reset-ignored").disabled = !!state.report_stale;
    const all = state.nested_duplicates || [],
      select = $("duplicate-owner"),
      old = select.value,
      owners = new Map();
    all.forEach((group) => {
      if (group.owner_id) owners.set(group.owner_id, group.owner_name || "МАФ");
    });
    mountView(select, [
      <option value={""}>{"Все МАФы"}</option>,
      viewList(
        Array.from(owners).map(([id, name]) => (
          <option value={id}>{name}</option>
        )),
      ),
    ]);
    select.value = owners.has(old) ? old : "";
    select.hidden = duplicateScope !== "nested";
    $("merge-nested").hidden = duplicateScope !== "nested";
    $("merge-nested").disabled = !!state.report_stale || !select.value;
    $("duplicate-whole-count").textContent = (state.duplicates || []).length;
    $("duplicate-other-count").textContent = (
      state.other_duplicates || []
    ).length;
    $("duplicate-nested-count").textContent = all.length;
    document
      .querySelectorAll("[data-duplicate-scope]")
      .forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.duplicateScope === duplicateScope),
        ),
      );
    $("duplicate-scope-info").textContent =
      duplicateScope === "ignored"
        ? "Исключённые пары сохраняются между анализами. Можно вернуть одну пару в проверку или сбросить все исключения."
        : duplicateScope === "whole"
          ? "Распознанные МАФы целиком, включая объекты внутри общих контейнеров."
          : duplicateScope === "other"
            ? "Совпадения других моделей проекта, включая нераспознанные компоненты и группы. Решение о распознавании не изменяется."
            : "Совпадения деталей показаны отдельно для каждого распознанного МАФа.";
  }
  function renderSections() {
    if (activePage !== "sections") return;
    const sections = state.sections || [];
    mountView(
      $("sections-list"),
      viewList(
        sections.map((section) => {
          const project = (state.models || [])
              .filter((x) => x.category === section && x.is_maf === true)
              .reduce((sum, x) => sum + (x.instances || 0), 0),
            library = (state.catalog || []).filter(
              (x) => x.category === section,
            ).length;
          return (
            <SectionRow
              library={library}
              project={project}
              section={section}
              key={section}
            />
          );
        }),
      ),
    );
  }
  function previewKey(id, ids) {
    return id + ":" + JSON.stringify(ids.slice().sort());
  }
  function comparison(group) {
    const defs = visibleDefinitions(group),
      ids = defs.map((d) => String(d.id)),
      images = duplicatePreviews.get(previewKey(group.id, ids)) || {},
      loaded = duplicatePreviews.has(previewKey(group.id, ids));
    return (
      <>
        <div className={"table-wrap"}>
          <table className={"table duplicate-comparison"}>
            <thead>
              <tr>
                <th>{"Превью"}</th>
                <th>{"Определение"}</th>
                <th>{"Габариты"}</th>
                <th>{"Геометрия"}</th>
                <th>{"Размещений"}</th>
              </tr>
            </thead>
            <tbody>
              {viewList(
                defs.map((d) => {
                  const meta = definitionMetadata(d.id),
                    image = images[d.id];
                  return (
                    <tr>
                      <td>
                        <div
                          className={"compare-image"}
                          data-preview-definition={d.id}
                        >
                          {image ? (
                            <img src={image} alt={"Превью: " + d.name}></img>
                          ) : loaded ? (
                            "Нет превью"
                          ) : (
                            "Не загружено"
                          )}
                        </div>
                      </td>
                      <td>
                        {d.name}
                        <span className={"sub"}>
                          {"ID: "}
                          {d.id}
                        </span>
                      </td>
                      <td>{dimensions(meta)}</td>
                      <td>{geometryText(meta)}</td>
                      <td>{d.instances || 0}</td>
                    </tr>
                  );
                }),
              )}
            </tbody>
          </table>
        </div>
        <div className={"duplicate-actions"}>
          <button
            className={"button small"}
            data-load-previews={group.id}
            data-preview-ids={JSON.stringify(ids)}
            {...(state.report_stale || ids.length > 30
              ? {
                  disabled: true,
                }
              : {})}
          >
            {ids.length > 30
              ? "Превью: группа больше 30 моделей"
              : "Загрузить превью"}
          </button>
          <span className={"hint"}>
            {group.classification === "confirmed" && group.replaceable === true
              ? "Совпала полная доступная сигнатура. Проверьте модели перед заменой."
              : "Сходство требует проверки; автоматическая замена заблокирована."}
          </span>
        </div>
      </>
    );
  }
  function renderPlacements() {
    const groups = state.placement_groups || [];
    $("duplicate-scope-info").textContent =
      "Размещения одного определения. Выберите конкретный объект, чтобы показать его в модели.";
    mountView($("duplicates-list"), [
      state.report_stale ? (
        <div className={"callout"}>{"Отчёт устарел. Запустите анализ."}</div>
      ) : (
        ""
      ),
      groups.length
        ? viewList(
            pageItems("duplicates", groups).map((group) => (
              <PlacementGroup
                group={group}
                placementDefinition={placementDefinition}
                state={state}
                key={group.id}
                children={placementItems()}
              />
            )),
          )
        : (pageItems("duplicates", []),
          (
            <div className={"empty"}>{"Повторных размещений не найдено."}</div>
          )),
    ]);
  }
  function requestPlacements(id, offset) {
    if (state.report_stale) return;
    placementDefinition = String(id);
    placementData = null;
    renderPlacements();
    send(
      "list_placements",
      placementDefinition,
      offset,
      String(++placementRequest),
    );
  }
  function patchPlacements() {
    renderPlacements();
  }
  function placementItems() {
    const data = placementData;
    if (!data) return "Загрузка размещений…";
    return [
      viewList(
        (data.items || []).map((item) => (
          <label className={"list-item"}>
            <span>
              <input
                type={"radio"}
                name={"placement"}
                data-placement-choice={""}
                value={item.id}
                {...(state.report_stale
                  ? {
                      disabled: true,
                    }
                  : {})}
              ></input>{" "}
              {item.label || item.name || item.id}
              <span className={"sub"}>{(item.path || []).join(" / ")}</span>
            </span>
            <button
              className={"button small"}
              data-focus-placement={item.id}
              {...(state.report_stale
                ? {
                    disabled: true,
                  }
                : {})}
            >
              {"Показать"}
            </button>
          </label>
        )),
      ),
      <div className={"page-controls"}>
        <button
          className={"button small"}
          data-placement-offset={Math.max(0, data.offset - data.limit)}
          {...(data.offset === 0
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Назад"}
        </button>
        <span>
          {data.offset + 1}
          {"–"}
          {Math.min(data.offset + data.limit, data.total)}
          {" из "}
          {data.total}
        </span>
        <button
          className={"button small"}
          data-placement-offset={data.offset + data.limit}
          {...(data.offset + data.limit >= data.total
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Далее"}
        </button>
      </div>,
    ];
  }
  function definitionPager(group) {
    if (group.definitions.length <= 20) return "";
    const key = definitionKey(group),
      page = definitionPages.get(key) || 0,
      total = Math.ceil(group.definitions.length / 20);
    return (
      <div className={"page-controls"}>
        <button
          className={"button small"}
          data-definition-prev={key}
          {...(page === 0
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Назад"}
        </button>
        <span>
          {"Определения: "}
          {page * 20 + 1}
          {"–"}
          {Math.min((page + 1) * 20, group.definitions.length)}
          {" из "}
          {group.definitions.length}
        </span>
        <button
          className={"button small"}
          data-definition-next={key}
          {...(page + 1 >= total
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Далее"}
        </button>
      </div>
    );
  }
  function ignoreControls(group) {
    if (group.definitions.length > 2) {
      const key = definitionKey(group),
        selected = pairSelections.get(key) || new Set();
      return (
        <button
          className={"button small"}
          data-ignore-group={key}
          data-ignore-group-id={group.id}
          {...(state.report_stale || selected.size !== 2
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Не дубли (выберите два определения)"}
        </button>
      );
    }
    if (group.definitions.length !== 2) return "";
    return (
      <button
        className={"button small"}
        data-ignore-pair={JSON.stringify([
          group.id,
          ...group.definitions.map((d) => d.id),
        ])}
        {...(state.report_stale
          ? {
              disabled: true,
            }
          : {})}
      >
        {duplicateScope === "ignored" ? "Вернуть в проверку" : "Не дубли"}
      </button>
    );
  }
  function patchDuplicatePreviews() {
    // Reconcile the current bounded page so React retains card and input identity.
    render();
  }
  function renderCleanup() {
    if (activePage !== "cleanup") return;
    const cleanup = state.cleanup || {},
      items = cleanup.unused_items || [],
      stale = !!state.report_stale;
    const valid = new Set(items.map((item) => String(item.id)));
    cleanupSelection = new Set(
      Array.from(cleanupSelection).filter((id) => valid.has(id)),
    );
    $("cleanup-info").textContent = stale
      ? "Отчёт устарел. Запустите анализ перед очисткой."
      : items.length
        ? "Выберите определения без размещений в проекте или вложенных компонентах."
        : "Неиспользуемых определений не найдено. Если анализ ещё не запускался, нажмите «Анализировать».";
    mountView(
      $("cleanup-list"),
      viewList(
        items.map((item) => (
          <CleanupRow
            cleanupSelection={cleanupSelection}
            item={item}
            stale={stale}
            key={item.id}
          />
        )),
      ),
    );
    $("cleanup-selected").disabled = stale || cleanupSelection.size === 0;
  }
  function render() {
    focusGroups.clear();
    clearInactivePages();
    const s = state.summary || {};
    const models = state.models || [];
    const summaryChanged = summarySource !== models;
    if (summaryChanged) {
      summarySource = models;
      summaryKnown = models.filter((x) => x.is_maf === true);
      summaryUnknown = models.filter((x) => !x.is_maf);
    }
    const known = summaryKnown;
    const unknown = summaryUnknown;
    if (summaryChanged) {
      $("accounting-summary").textContent =
        `Подтверждено МАФ: ${known.reduce((n, row) => n + (row.definitions || 0), 0)} определений / ${known.reduce((n, x) => n + (x.instances || 0), 0)} размещений. Неизвестных моделей: ${unknown.reduce((n, row) => n + (row.definitions || 0), 0)} определений / ${unknown.reduce((n, x) => n + (x.instances || 0), 0)} размещений. Скрытых размещений: ${models.reduce((n, x) => n + (x.hidden_instances || 0), 0)}; скрытых тегов: ${(state.summary || {}).hidden_tags || 0}.`;
      $("category-summary").textContent =
        "МАФ по разделам: " +
        Object.entries(
          known.reduce((a, x) => {
            const k = x.category || "Без категории";
            a[k] = (a[k] || 0) + (x.instances || 0);
            return a;
          }, {}),
        )
          .map(([k, v]) => `${k}: ${v}`)
          .join(" · ");
    }
    $("report-stale").hidden = !state.report_stale;
    $("all-component-count").textContent =
      `${s.all_component_instances || 0} размещений · ${s.all_component_definitions || 0} определений`;
    $("maf-count").textContent =
      `${s.maf_instances || 0} размещений · ${s.maf_definitions || 0} определений`;
    $("m-unique").textContent = s.unique || 0;
    $("m-duplicates").textContent = s.duplicate_groups || 0;
    $("nav-duplicates").textContent =
      (state.duplicates || []).length + (state.other_duplicates || []).length;
    $("nav-catalog").textContent = (state.catalog || []).length;
    $("insight").textContent =
      ((state.duplicates || []).length
        ? `Найдено групп дублей: ${state.duplicates.length}. Сначала проверьте эталон, затем заменяйте.`
        : (state.other_duplicates || []).length
          ? `Найдено групп совпадений других моделей: ${state.other_duplicates.length}. Откройте раздел «Другие модели проекта».`
          : "Повторяющихся определений не найдено.") +
      (s.sampled_definitions
        ? ` Крупных определений проверено выборочно: ${s.sampled_definitions}.`
        : "");
    renderSelectOptions();
    renderModels();
    renderRecognition();
    renderCatalog();
    renderSyncErrors();
    renderSections();
    $("unused-count").textContent =
      (state.cleanup || {}).unused_definitions || 0;
    $("cleanup-duplicates").textContent = (state.duplicates || []).length;
    renderCleanup();
    $("path-personal").textContent =
      (state.settings || {}).personal || "Не задан";
    $("path-shared").textContent = (state.settings || {}).shared || "Не задан";
    $("cloud-url").value = (state.settings || {}).cloud_url || "";
    if (activePage === "duplicates" && duplicateScope === "placements") {
      renderDuplicateControls();
      renderPlacements();
    } else if (activePage === "duplicates") {
      renderDuplicateControls();
      const visibleDuplicates = duplicateItems();
      mountView($("duplicates-list"), [
        state.report_stale ? (
          <div className={"callout"}>
            {
              "Отчёт устарел. Запустите анализ, чтобы сравнить актуальные модели."
            }
          </div>
        ) : (
          ""
        ),
        visibleDuplicates.length
          ? viewList(
              pageItems("duplicates", visibleDuplicates).map((group) => (
                <DuplicateCard
                  batchControls={batchControls}
                  comparison={comparison}
                  definitionKey={definitionKey}
                  definitionPager={definitionPager}
                  duplicateScope={duplicateScope}
                  focusGroupKey={focusGroupKey}
                  group={group}
                  ignoreControls={ignoreControls}
                  pairSelections={pairSelections}
                  state={state}
                  viewList={viewList}
                  visibleDefinitions={visibleDefinitions}
                  key={group.id}
                />
              )),
            )
          : (pageItems("duplicates", []),
            (
              <div className={"empty"}>
                {"В этом разделе совпадений не найдено."}
              </div>
            )),
      ]);
    }
    $("focus-duplicates").disabled =
      !!state.report_stale || duplicateSelection.size === 0;
  }
  function setPage(name) {
    closeMenu();
    activePage = name;
    document
      .querySelectorAll(".page")
      .forEach((el) => el.classList.toggle("active", el.id === name));
    document
      .querySelectorAll(".nav [data-page]")
      .forEach((el) => el.classList.toggle("active", el.dataset.page === name));
    $("page-title").textContent =
      {
        overview: "Обзор модели",
        duplicates: "Поиск дублей",
        catalog: "Библиотека МАФ",
        sections: "Разделы МАФ",
        cleanup: "Очистка модели",
        settings: "Настройки",
      }[name] || "МАФ Каталог";
    render();
    if (name === "duplicates" && !demo && !state.report_stale) {
      const button = Array.from(
        document.querySelectorAll("[data-load-previews]:not([disabled])"),
      ).find((item) => JSON.parse(item.dataset.previewIds).length <= 6);
      if (button) {
        const ids = JSON.parse(button.dataset.previewIds);
        if (
          !duplicatePreviews.has(previewKey(button.dataset.loadPreviews, ids))
        )
          send(
            "duplicate_previews",
            button.dataset.loadPreviews,
            ids,
            String(previewEpoch),
          );
      }
    }
  }
  function setSelection(ids, notify = true) {
    selectedIds = new Set(ids);
    renderSelection();
    if (notify) {
      if (demo) {
        status(
          `Выделено строк: ${selectedIds.size}. В SketchUp соответствующие компоненты подсветятся в сцене.`,
          "success",
        );
      } else send("select_rows", Array.from(selectedIds));
    }
  }
  function selectRow(row, event) {
    const id = row.dataset.row,
      nodeId = row.dataset.node,
      visible = Array.from(
        document.querySelectorAll("#models-body .model-row"),
      );
    if (
      event.shiftKey &&
      anchorId &&
      visible.some((item) => item.dataset.node === anchorId)
    ) {
      const from = visible.findIndex((item) => item.dataset.node === anchorId),
        to = visible.indexOf(row),
        range = visible.slice(Math.min(from, to), Math.max(from, to) + 1);
      selectedNodeIds = new Set(range.map((item) => item.dataset.node));
      setSelection(range.map((item) => item.dataset.row));
    } else if (event.ctrlKey || event.metaKey) {
      const allNodes = [];
      const collect = (nodes) =>
        (nodes || []).forEach((node) => {
          allNodes.push(node);
          collect(node.children);
        });
      collect(
        state.hierarchy ||
          (state.models || []).map((item) => ({
            id: item.id,
            row_id: item.id,
          })),
      );
      // External selection has definition IDs only: materialize its visible branch selection before toggling.
      if (!selectedNodeIds.size && selectedIds.size)
        selectedNodeIds = new Set(
          allNodes
            .filter((node) => selectedIds.has(node.row_id))
            .map((node) => node.id),
        );
      selectedNodeIds.has(nodeId)
        ? selectedNodeIds.delete(nodeId)
        : selectedNodeIds.add(nodeId);
      setSelection(
        allNodes
          .filter((node) => node.row_id && selectedNodeIds.has(node.id))
          .map((node) => node.row_id),
      );
      anchorId = nodeId;
    } else {
      selectedNodeIds = new Set([nodeId]);
      setSelection([id]);
      anchorId = nodeId;
    }
  }
  function openMenu(x, y, trigger) {
    if (!selectedIds.size) return;
    contextTrigger = trigger;
    const menu = $("context-menu");
    menu.classList.add("open");
    const selectedRow = (state.models || []).find((item) =>
      selectedIds.has(item.id),
    );
    menu.querySelector('[data-action="rename"]').disabled =
      selectedIds.size !== 1 ||
      !selectedRow ||
      selectedRow.definition_ids.length !== 1;
    const left = Math.min(x, window.innerWidth - menu.offsetWidth - 8),
      top = Math.min(y, window.innerHeight - menu.offsetHeight - 8);
    menu.style.left = Math.max(8, left) + "px";
    menu.style.top = Math.max(8, top) + "px";
    menu.querySelector("button:not(:disabled)").focus();
  }
  function closeMenu() {
    $("context-menu").classList.remove("open");
  }
  function renderGlobalScope(rows) {
    $("action-scope").hidden = false;
    $("action-scope").textContent =
      `Действие со всеми размещениями определения по всему проекту: ${rows.reduce((n, row) => n + (row.instances || 0), 0)}.\nПути: ${Array.from(new Set(flattenMap(rows, (row) => row.paths || []))).join(" · ") || "Пути недоступны — повторите анализ."}${state.report_stale ? "\nОтчёт устарел. Перед действием повторите анализ." : ""}`;
  }
  function showModal(kind, trigger, group) {
    closeCatalogMenu();
    closeMenu();
    modalKind = kind;
    modalIds = Object.freeze(Array.from(selectedIds));
    actionInvalidated = false;
    modalTrigger = trigger || document.activeElement;
    duplicateGroup = group || null;
    const count = modalIds.slice().reduce((sum, id) => {
      const row = (state.models || []).find((item) => item.id === id);
      return sum + (row ? row.instances || 0 : 0);
    }, 0);
    $("modal-status").hidden = true;
    $("modal-category-field").hidden = true;
    $("action-scope").hidden = true;
    $("action-scope").textContent = "";
    $("modal-input-field").hidden = true;
    $("modal-select-field").hidden = true;
    $("modal-summary").hidden = true;
    $("paste-zone").hidden = true;
    $("modal-input").value = "";
    $("paste-zone").textContent = "";
    $("modal-eyebrow").textContent = "ДЕЙСТВИЕ С МОДЕЛЯМИ";
    $("modal-description").textContent = "";
    $("confirm").disabled = false;
    $("manual-accept-field").hidden = true;
    $("manual-accept").checked = false;
    manualPreviewToken = "";
    manualPreviewReady = false;
    if (
      [
        "rename",
        "section",
        "add-library",
        "delete",
        "replace",
        "duplicate",
        "manual-duplicate",
      ].includes(kind) ||
      kind.startsWith("decision-")
    ) {
      const rows =
        kind === "duplicate" || kind === "manual-duplicate"
          ? (state.models || []).filter((row) =>
              (group.definitions || []).some((def) =>
                (row.definition_ids || []).includes(def.id),
              ),
            )
          : (state.models || []).filter((row) => modalIds.includes(row.id));
      renderGlobalScope(rows);
      if (state.report_stale) $("confirm").disabled = true;
    }
    if (kind.startsWith("decision-")) {
      $("modal-title").textContent = {
        "decision-confirmed": "Подтвердить МАФ",
        "decision-rejected": "Отклонить МАФ",
        "decision-clear": "Сбросить решение",
      }[kind];
      $("modal-description").textContent =
        "Решение применяется к определению и всем его размещениям. Подтверждённая модель без карточки автоматически сохранится в личную библиотеку.";
    }
    if (kind === "copy-selected") {
      $("modal-title").textContent = "Создать копию выделенного";
      $("modal-description").textContent =
        "Выделите один компонент или группу в SketchUp. Исходная карточка останется в своей библиотеке; новая копия получит отдельный файл и связь с выделенной моделью.";
      $("modal-input-field").hidden = false;
      $("modal-input-label").textContent = "Название копии";
      $("modal-select-field").hidden = false;
      $("modal-select-label").textContent = "Библиотека";
      mountView(
        $("modal-select"),
        <>
          <option value={"personal"}>{"Личная"}</option>
          <option value={"shared"}>{"Общая локальная"}</option>
        </>,
      );
      $("modal-select").value = $("import-scope").value;
      $("modal-category-field").hidden = false;
      mountView(
        $("modal-category"),
        viewList(
          (state.sections && state.sections.length
            ? state.sections
            : ["Другое"]
          ).map((section) => <option>{section}</option>),
        ),
      );
    }
    if (kind === "update-selected") {
      $("modal-title").textContent = "Обновить из выделенного?";
      $("modal-description").textContent = "Проверяем выделенный компонент или группу…";
      $("confirm").disabled = true;
      call("preview_selected_card_update", selectedUpdateTarget.id, selectedUpdateTarget.scope, selectedUpdateTarget.token);
    }
    if (kind === "update-version") {
      $("modal-title").textContent = "Обновить версию карточки?";
      $("modal-description").textContent =
        "Сохранить новую версию .skp из связанного определения. Текущий файл карточки будет заменён только после этого подтверждения.";
      const rows = (state.models || []).filter(
        (row) =>
          row.catalog_id === versionTarget.id &&
          row.recognized_catalog_scope === versionTarget.scope,
      );
      const defs = flattenMap(rows, (row) =>
        (row.definition_ids || []).map((id) => ({
          id,
          name: row.name,
        })),
      );
      $("modal-select-field").hidden = !defs.length;
      $("modal-select-label").textContent = "Определение для новой версии";
      mountView(
        $("modal-select"),
        viewList(
          defs.map((def) => (
            <option value={def.id}>
              {def.name}
              {" · "}
              {def.id}
            </option>
          )),
        ),
      );
      if (!defs.length)
        $("modal-description").textContent +=
          " Будет прочитан выделенный компонент в SketchUp.";
      if (state.report_stale && defs.length) $("confirm").disabled = true;
    }
    if (kind === "rename") {
      const row = (state.models || []).find((item) =>
        modalIds.includes(item.id),
      );
      const match = (state.duplicates || []).find(
        (item) =>
          row &&
          item.definitions.some((def) => row.definition_ids.includes(def.id)),
      );
      $("modal-title").textContent = "Переименовать модель";
      $("modal-description").textContent =
        row && row.kind === "group"
          ? "Имя выбранной группы изменится в проекте."
          : "Имя определения компонента изменится в проекте.";
      $("modal-input-field").hidden = false;
      $("modal-input-label").textContent = "Новое название";
      $("modal-input").value = row ? row.name : "";
      if (match) {
        const placements = match.definitions.reduce(
          (sum, item) => sum + (item.instances || 0),
          0,
        );
        $("modal-select-field").hidden = false;
        $("modal-select-label").textContent = "Что переименовать";
        mountView(
          $("modal-select"),
          <>
            <option value={"selected"}>{"Только выбранную модель"}</option>
            <option value={"all_names"}>{"Имена всех совпадений"}</option>
            <option
              value={"merge"}
              {...(match.replaceable === false || match.kind === "group"
                ? {
                    disabled: true,
                  }
                : {})}
            >
              {"Объединить все под выбранной моделью"}
              {match.kind === "group"
                ? " · объединение групп недоступно"
                : match.replaceable === false
                  ? " · проверка не пройдена"
                  : ""}
            </option>
          </>,
        );
        $("modal-summary").hidden = false;
        $("modal-summary").textContent =
          `Найдено ${match.definitions.length} совпадающих определений и ${placements} размещений. ${match.confidence}. ${match.kind === "group" ? "Объединение преобразует группы в компоненты." : "После переименования отдельных определений SketchUp может добавить суффиксы к их именам."} Объединение поддерживает Undo.`;
      }
    }
    if (kind === "catalog-section") {
      $("modal-title").textContent = "Изменить раздел карточки";
      $("modal-description").textContent =
        "Будет изменена карточка «" +
        catalogSectionTarget.name +
        "» в выбранной библиотеке. Раздел размещений в проекте сохраняется.";
      $("modal-select-field").hidden = false;
      $("modal-select-label").textContent = "Раздел";
      mountView(
        $("modal-select"),
        viewList(
          (state.sections || []).map((section) => (
            <option value={section}>{section}</option>
          )),
        ),
      );
      $("modal-select").value = catalogSectionTarget.category;
    }
    if (kind === "delete-section") {
      $("modal-title").textContent = "Удалить раздел?";
      $("modal-description").textContent =
        "Раздел «" +
        sectionDeleteTarget +
        "» будет удалён, если он не используется в проекте и библиотеках. Файлы моделей не удаляются.";
    }
    if (kind === "cleanup") {
      $("modal-title").textContent = "Удалить определения?";
      $("modal-description").textContent =
        "Будут удалены неиспользуемые определения: " +
        cleanupTarget.map((item) => item.name).join(", ") +
        ". Действие можно отменить через Undo.";
    }
    if (kind === "create-section") {
      $("modal-title").textContent = "Новый раздел";
      $("modal-description").textContent =
        "Раздел появится в проекте и фильтрах библиотеки.";
      $("modal-input-field").hidden = false;
      $("modal-input-label").textContent = "Название раздела";
    }
    if (kind === "section") {
      $("modal-title").textContent = `Добавить в раздел · ${modalIds.length}`;
      $("modal-description").textContent =
        "Раздел будет назначен всем выбранным определениям.";
      $("modal-select-field").hidden = false;
      $("modal-select-label").textContent = "Раздел";
      mountView($("modal-select"), [
        viewList(
          (state.sections || []).map((s) => <option value={s}>{s}</option>),
        ),
        <option value={"__new__"}>{"+ Новый раздел…"}</option>,
      ]);
    }
    if (kind === "add-library") {
      $("modal-title").textContent =
        `Добавить в библиотеку · ${modalIds.length}`;
      $("modal-description").textContent =
        "Каждое выбранное определение сохранится отдельным файлом .skp.";
      $("modal-select-field").hidden = false;
      $("modal-select-label").textContent = "Библиотека";
      mountView(
        $("modal-select"),
        <>
          <option value={"personal"}>{"Личная библиотека"}</option>
          <option value={"shared"}>{"Общая локальная библиотека"}</option>
        </>,
      );
    }
    if (kind === "delete") {
      $("modal-title").textContent = "Удалить из проекта?";
      $("modal-description").textContent =
        `Будут удалены размещения выбранных моделей: ${count}. Действие можно отменить через Undo.`;
      $("modal-summary").hidden = false;
      $("modal-summary").textContent = "Файлы в библиотеке останутся на месте.";
      $("confirm").textContent = "Удалить размещения";
      $("confirm").classList.add("danger");
    }
    if (kind === "replace" || kind === "duplicate") {
      const sourceIds = new Set(
        flattenMap(
          (state.models || []).filter((row) => modalIds.includes(row.id)),
          (row) => row.definition_ids || [],
        ),
      );
      const definitions =
        kind === "duplicate"
          ? group.definitions
          : (state.definitions || [])
              .filter(
                (d) =>
                  d.kind !== "group" &&
                  (sourceIds.size !== 1 || !sourceIds.has(d.id)),
              )
              .concat(
                (state.catalog || []).map((entry) => ({
                  id: `catalog:${entry.scope}:${entry.id}`,
                  name: `${entry.name} · ${scopeName(entry.scope)}`,
                  instances: 0,
                })),
              );
      $("modal-title").textContent =
        kind === "duplicate"
          ? `Заменить дубли: ${group.label}`
          : `Заменить выбранные модели · ${modalIds.length}`;
      $("modal-description").textContent =
        kind === "duplicate"
          ? `${group.confidence}${group.replaceable === false ? " · замена недоступна до подтверждения дубля" : ""}`
          : definitions.length
            ? "Будут затронуты выбранные модели проекта. Эталон можно взять из проекта или каталога."
            : "Нет доступного эталона для замены.";
      $("modal-select-field").hidden = definitions.length === 0;
      $("modal-select-label").textContent = "Эталонное определение";
      mountView(
        $("modal-select"),
        viewList(
          definitions.map((d) => (
            <option value={d.id}>
              {d.name}
              {" · "}
              {d.instances || 0}
              {" шт."}
            </option>
          )),
        ),
      );
      $("modal-summary").hidden = false;
      $("modal-summary").textContent = "Загрузка предпросмотра замены…";
      $("confirm").disabled = true;
    }
    if (kind === "batch-manual") {
      $("modal-title").textContent = "Пакетная замена на эталоны";
      $("modal-description").textContent =
        "Замена затронет все размещения исходных определений во всём проекте. Проверьте каждую группу и эталон. Все группы заменяются одним действием Undo.";
      $("manual-accept-field").hidden = false;
      $("action-scope").hidden = false;
      $("action-scope").textContent =
        "Область действия: весь проект, включая размещения за пределами текущего МАФа.";
      $("confirm").disabled = true;
    }
    if (kind === "manual-duplicate") {
      $("modal-title").textContent = "Заменить на эталон: " + group.label;
      $("modal-description").textContent =
        "Все размещения исходных определений во всём проекте будут использовать одно выбранное определение. Геометрия, внутренние материалы, динамические параметры и свойства исходных определений заменятся содержимым эталона. Положения и атрибуты размещений сохранятся. Доступна отмена через Undo.";
      $("modal-select-field").hidden = false;
      $("modal-select-label").textContent = "Эталонное определение";
      mountView(
        $("modal-select"),
        viewList(
          group.definitions.map((d) => (
            <option value={d.id}>
              {d.name}
              {" · "}
              {d.instances || 0}
              {" шт."}
            </option>
          )),
        ),
      );
      $("manual-accept-field").hidden = false;
      $("confirm").disabled = true;
    }
    if (kind === "nested-merge") {
      $("modal-title").textContent = "Объединить детали внутри МАФ?";
      $("modal-description").textContent =
        "Изменение затронет все размещения выбранного МАФа в проекте. Все детали останутся на своих местах. Действие можно отменить через Undo.";
      $("modal-summary").hidden = false;
      $("modal-summary").textContent =
        "Проверяем совпадения и область действия…";
      $("confirm").disabled = true;
    }
    if (kind === "delete-catalog") {
      const item = catalogDeleteTarget;
      $("modal-title").textContent = "Удалить из библиотеки?";
      $("modal-description").textContent =
        item.name +
        " · " +
        scopeName(item.scope) +
        ". Карточка исчезнет из каталога. Размещения в проекте, файл .skp и миниатюра останутся на месте. Повторный анализ не восстановит карточку; добавить её снова можно вручную.";
    }
    if (kind === "paste") {
      const item = catalogItem(imageTarget);
      $("modal-title").textContent =
        `Изображение: ${item ? item.name : "модель"}`;
      $("modal-description").textContent =
        "Сделайте снимок модели любым инструментом системы и вставьте его здесь.";
      $("paste-zone").hidden = false;
      $("confirm").hidden = true;
    }
    if (kind !== "paste") $("confirm").hidden = false;
    if (
      kind !== "delete" &&
      kind !== "delete-catalog" &&
      kind !== "delete-section" &&
      kind !== "cleanup"
    ) {
      $("confirm").textContent = "Применить";
      $("confirm").classList.remove("danger");
    }
    if (kind === "delete-section" || kind === "cleanup") {
      $("confirm").textContent = "Удалить";
      $("confirm").classList.add("danger");
    }
    if (kind === "delete-catalog") {
      $("confirm").textContent = "Удалить из библиотеки";
      $("confirm").classList.add("danger");
    }
    $("modal-backdrop").classList.add("open");
    const focusTarget =
      kind === "paste"
        ? $("paste-zone")
        : kind === "rename" || kind === "create-section"
          ? $("modal-input")
          : !$("modal-select-field").hidden
            ? $("modal-select")
            : $("confirm");
    focusTarget.focus();
    if (kind === "replace" || kind === "duplicate") requestReplacementPreview();
    if (kind === "manual-duplicate") requestManualReplacementPreview();
    if (kind === "batch-manual") requestBatchPreview();
    if (kind === "nested-merge") {
      nestedMergeToken = String(++previewToken);
      if (!send("preview_nested_merge", nestedMergeOwner, nestedMergeToken)) {
        $("modal-summary").textContent = "Предпросмотр доступен в SketchUp.";
      }
    }
  }
  function requestManualReplacementPreview() {
    $("modal-status").hidden = false;
    $("modal-status").textContent =
      "Применение недоступно: ожидается проверка размещений.";
    manualPreviewToken = "";
    manualPreviewReady = false;
    $("manual-accept").checked = false;
    $("confirm").disabled = true;
    const token = String(++previewToken);
    $("modal-summary").hidden = false;
    $("modal-summary").textContent =
      "Проверяем все размещения определения во всём проекте…";
    if (
      !send(
        "preview_manual_replace_duplicates",
        duplicateGroup.id,
        $("modal-select").value,
        token,
      )
    )
      $("modal-summary").textContent = "Предпросмотр доступен в SketchUp.";
  }
  function renderManualReplacementPreview(payload) {
    if (
      modalKind !== "manual-duplicate" ||
      !duplicateGroup ||
      String(payload.token) !== String(previewToken) ||
      String(payload.group_id) !== String(duplicateGroup.id) ||
      String(payload.target_id) !== $("modal-select").value
    )
      return;
    manualPreviewToken = payload.preview_token || "";
    const plan = payload.plan || {},
      blockers = plan.blockers || [];
    manualPreviewReady =
      !payload.error &&
      !!manualPreviewToken &&
      plan.entities > 0 &&
      !blockers.length;
    const summary = $("modal-summary");
    summary.style.whiteSpace = "normal";
    summary.textContent = payload.error
      ? "Предпросмотр недоступен: " + payload.error
      : `Замена: ${(plan.sources || []).join(", ")} → ${plan.target || "—"}. Весь проект: экземпляров ${plan.entities || 0}; размещений ${plan.placements || 0}. ` +
        (plan.warning ||
          "Геометрия, внутренние материалы и свойства будут заменены эталоном. Размещения сохраняются. Доступна отмена через Undo.");
    previewIssues(summary, plan.warnings || [], "Предупреждения");
    previewIssues(summary, blockers, "Блокировки");
    previewPaths(summary, plan.paths || []);
    updateManualConfirmation();
  }
  function updateManualConfirmation() {
    const ready =
      modalKind === "batch-manual" ? batchReady : manualPreviewReady;
    $("modal-status").hidden = ready;
    $("modal-status").textContent =
      "Применение недоступно: предпросмотр не подтверждён или найдены блокировки. Устраните указанные ограничения и повторите проверку.";
    if (modalKind === "batch-manual")
      $("confirm").disabled =
        actionInvalidated ||
        !!state.report_stale ||
        !batchReady ||
        batchSnapshot !== JSON.stringify(batchRequests()) ||
        !$("manual-accept").checked;
    if (modalKind === "manual-duplicate")
      $("confirm").disabled =
        actionInvalidated ||
        !!state.report_stale ||
        !manualPreviewReady ||
        !$("manual-accept").checked;
  }
  function requestReplacementPreview() {
    const token = String(++previewToken),
      value = $("modal-select").value;
    const summary = $("modal-summary");
    $("confirm").disabled = true;
    summary.hidden = false;
    summary.textContent = "Выполняется проверка размещений и ограничений…";
    if (demo) {
      setTimeout(
        () =>
          window.MAF.receive({
            replacement_preview: {
              token,
              plan: {
                sources:
                  modalKind === "duplicate" && duplicateGroup
                    ? duplicateGroup.definitions
                        .filter((x) => x.id !== value)
                        .map((x) => x.name)
                    : modalIds
                        .slice()
                        .map(
                          (id) =>
                            (
                              (state.models || []).find((x) => x.id === id) ||
                              {}
                            ).name || id,
                        ),
                target:
                  ((state.definitions || []).find((x) => x.id === value) || {})
                    .name || value,
                entities: 1,
                placements: 1,
                paths: ["Демо / модель"],
                blockers: [],
              },
            },
          }),
        0,
      );
      return;
    }
    if (modalKind === "duplicate")
      send("preview_replace_duplicates", duplicateGroup.id, value, token);
    else send("preview_replace_rows", modalIds.slice(), value, token);
  }
  function renderReplacementPreview(payload) {
    if (
      String(payload.token) !== String(previewToken) ||
      !["replace", "duplicate"].includes(modalKind)
    )
      return;
    const summary = $("modal-summary");
    summary.hidden = false;
    if (payload.error) {
      summary.textContent = `Предпросмотр недоступен: ${payload.error}`;
      $("confirm").disabled = true;
      return;
    }
    const plan = payload.plan || {},
      lines = [
        `Замена: ${(plan.sources || []).join(", ") || "—"} → ${plan.target || "—"}`,
        `Затронет экземпляров: ${plan.entities || 0}; размещений: ${plan.placements || 0}`,
        `Пути в модели: ${(plan.paths || []).join(" · ") || "не найдены"}`,
      ];
    const blockers = plan.blockers || [];
    if (blockers.length)
      lines.push(
        `Блокировки: ${blockers.map((x) => `${x.name ? x.name + ": " : ""}${x.reason}${x.paths && x.paths.length ? " (" + x.paths.join(" · ") + ")" : ""}`).join(" | ")}`,
      );
    else lines.push("Ограничений для замены не найдено.");
    summary.textContent = lines.join("\n");
    summary.style.whiteSpace = "pre-wrap";
    $("confirm").disabled =
      actionInvalidated ||
      !!state.report_stale ||
      blockers.length > 0 ||
      !(plan.entities > 0);
  }
  function renderNestedMergePreview(payload) {
    if (
      modalKind !== "nested-merge" ||
      String(payload.token) !== nestedMergeToken ||
      String(payload.owner_id) !== nestedMergeOwner
    )
      return;
    const summary = $("modal-summary");
    summary.hidden = false;
    summary.style.whiteSpace = "pre-wrap";
    if (payload.error) {
      summary.textContent = "Предпросмотр недоступен: " + payload.error;
      $("confirm").disabled = true;
      return;
    }
    const details = Array.isArray(payload.details) ? payload.details : [];
    summary.textContent = [
      `МАФ: ${payload.owner_name || "—"}`,
      `Групп к объединению: ${payload.groups || 0}; определений: ${payload.definitions || 0}; размещений: ${payload.placements || 0}`,
      `Пропущено групп: ${payload.skipped || 0}`,
    ]
      .concat(
        details.map(
          (item) =>
            `${item.label || "Деталь"}: ${
              {
                eligible: "Можно объединить",
                skipped: "Пропущено",
              }[item.status] || "Требует проверки"
            }${item.target ? " → " + item.target : ""}${item.reason ? " · " + item.reason : ""}`,
        ),
      )
      .join("\n");
    $("confirm").disabled =
      actionInvalidated || !!state.report_stale || !(payload.groups > 0);
  }
  function closeModal() {
    selectedUpdateTarget = null;
    previewToken++;
    $("modal-backdrop").classList.remove("open");
    modalKind = "";
    duplicateGroup = null;
    if (modalTrigger) modalTrigger.focus();
    if (syncWarningsPending) openSyncWarnings();
  }
  function reconcileDemo() {
    const rows = new Map((state.models || []).map((row) => [row.id, row])),
      placements = new Map();
    const visit = (nodes) =>
      (nodes || [])
        .filter((node) => !node.row_id || rows.has(node.row_id))
        .map((node) => {
          const row = rows.get(node.row_id),
            children = visit(node.children);
          if (row)
            placements.set(
              row.id,
              (placements.get(row.id) || 0) + (node.instances || 0),
            );
          return {
            ...node,
            name: row ? row.name : node.name,
            is_maf: row ? row.is_maf : false,
            children,
            has_maf_descendant: children.some(
              (child) => child.is_maf || child.has_maf_descendant,
            ),
          };
        });
    state.hierarchy = visit(state.hierarchy);
    state.models = state.models
      .filter((row) => placements.has(row.id))
      .map((row) => ({
        ...row,
        instances: placements.get(row.id),
      }));
    const byDefinition = new Map(
      flattenMap(state.models, (row) =>
        row.definition_ids.map((id) => [id, row]),
      ),
    );
    state.definitions = (state.definitions || [])
      .filter((def) => byDefinition.has(def.id))
      .map((def) => ({
        ...def,
        name: byDefinition.get(def.id).name,
      }));
    state.duplicates = (state.duplicates || [])
      .map((group) => ({
        ...group,
        definitions: group.definitions
          .filter((def) => byDefinition.has(def.id))
          .map((def) => ({
            ...def,
            name: byDefinition.get(def.id).name,
          })),
      }))
      .filter((group) => group.definitions.length > 1);
    const sum = (items, key) =>
        items.reduce((total, item) => total + (item[key] || 0), 0),
      components = state.models.filter((row) => row.kind === "component"),
      maf = state.models.filter((row) => row.is_maf);
    Object.assign(state.summary, {
      instances: sum(state.models, "instances"),
      definitions: sum(state.models, "definitions"),
      all_component_instances: sum(components, "instances"),
      all_component_definitions: sum(components, "definitions"),
      maf_instances: sum(maf, "instances"),
      maf_definitions: sum(maf, "definitions"),
      duplicate_groups: state.duplicates.length,
    });
    state.summary.unique =
      state.summary.definitions -
      state.duplicates.reduce(
        (total, group) => total + group.definitions.length - 1,
        0,
      );
    state.catalog.forEach((card) => {
      card.project_placements = sum(
        maf.filter(
          (row) =>
            row.recognized_catalog &&
            row.catalog_id === card.id &&
            row.recognized_catalog_scope === card.scope,
        ),
        "instances",
      );
    });
    selectedIds = new Set(
      Array.from(selectedIds).filter((id) =>
        state.models.some((row) => row.id === id),
      ),
    );
  }
  function demoAction(action, args) {
    if (action === "delete_section") {
      state.sections = state.sections.filter((section) => section !== args[0]);
      status("Демо: раздел удалён.", "success");
    } else if (action === "change_catalog_section") {
      const item = state.catalog.find(
        (x) => x.id === args[0] && x.scope === args[1],
      );
      if (item) item.category = args[2];
      status("Демо: раздел карточки изменён.", "success");
    } else if (action === "remove_unused_definitions") {
      state.cleanup.unused_items = (state.cleanup.unused_items || []).filter(
        (item) => !args[0].includes(String(item.id)),
      );
      state.cleanup.unused_definitions = state.cleanup.unused_items.length;
      cleanupSelection.clear();
      status("Демо: определения удалены.", "success");
    } else if (action === "delete_catalog_model") {
      if (args[1] !== "personal") {
        status("Удаление из общей библиотеки запрещено.", "error");
        return;
      }
      state.catalog = state.catalog.filter(
        (item) => item.id !== args[0] || item.scope !== args[1],
      );
      status(
        "Демо: модель удалена из библиотеки. Размещения в проекте сохранены.",
        "success",
      );
    } else if (action === "rename_rows") {
      const row = (state.models || []).find((x) => x.id === args[0][0]);
      const oldName = row.name;
      row.name = args[1];
      row.paths = (row.paths || []).map((path) =>
        path.split(oldName).join(row.name),
      );
      status("Демо: модель переименована.", "success");
    } else if (action === "move_rows") {
      (state.models || [])
        .filter((x) => args[0].includes(x.id))
        .forEach((x) => (x.category = args[1]));
      status("Демо: раздел назначен.", "success");
    } else if (action === "create_section") {
      state.sections.push(args[0]);
      status("Демо: раздел создан.", "success");
    } else if (action === "delete_rows") {
      state.models = state.models.filter((x) => !args[0].includes(x.id));
      state.summary.instances = state.models.reduce(
        (s, x) => s + x.instances,
        0,
      );
      state.summary.definitions = state.models.reduce(
        (s, x) => s + x.definitions,
        0,
      );
      selectedIds.clear();
      selectedNodeIds.clear();
      status("Демо: размещения удалены.", "success");
    } else if (action === "add_rows_to_library") {
      const rows = state.models.filter((x) => args[0].includes(x.id));
      rows.forEach((row, i) =>
        state.catalog.push({
          id: "demo-" + Date.now() + "-" + i,
          name: row.name,
          category: row.category,
          scope: args[1],
        }),
      );
      status("Демо: модели добавлены в библиотеку.", "success");
    } else if (action === "focus_rows") {
      status("Демо: камера покажет размещения модели.", "success");
    } else if (action === "focus_duplicates") {
      status(
        `Демо: выбрано дублей: ${args[0].length}. В SketchUp камера покажет их размещения.`,
        "success",
      );
    } else if (action === "replace_rows" || action === "replace_duplicates") {
      status(
        "Демо: замена подтверждена. Реальная операция выполняется в SketchUp.",
        "success",
      );
    } else if (action === "set_thumbnail") {
      const entry = catalogItem(args[0]);
      if (entry) entry.thumbnail = args[1];
      status("Демо: изображение обновлено.", "success");
    } else if (action === "set_cloud_url") {
      state.settings.cloud_url = args[0];
      status(
        "Демо: адрес сохранен. Синхронизация работает в SketchUp.",
        "success",
      );
    } else {
      status("Это действие доступно после установки расширения в SketchUp.");
    }
    reconcileDemo();
    render();
  }
  function call(action, ...args) {
    if (!send(action, ...args)) demoAction(action, args);
  }
  function submitModal() {
    if (actionInvalidated || $("confirm").disabled) return;
    const kind = modalKind,
      ids = modalIds.slice(),
      value = $("modal-select").value,
      input = $("modal-input").value.trim();
    if (kind === "batch-manual") {
      if (
        !batchReady ||
        !batchServerToken ||
        batchSnapshot !== JSON.stringify(batchRequests()) ||
        !$("manual-accept").checked ||
        state.report_stale
      )
        return;
      call(
        "batch_manual_replace_duplicates",
        JSON.stringify(batchRequests()),
        batchServerToken,
        true,
      );
    } else if (kind === "manual-duplicate") {
      if (
        !manualPreviewReady ||
        !manualPreviewToken ||
        !$("manual-accept").checked
      )
        return;
      call(
        "manual_replace_duplicates",
        duplicateGroup.id,
        value,
        manualPreviewToken,
        true,
      );
    } else if (kind === "nested-merge") {
      call("merge_nested_duplicates", nestedMergeOwner, nestedMergeToken);
    } else if (kind === "catalog-section") {
      call(
        "change_catalog_section",
        catalogSectionTarget.id,
        catalogSectionTarget.scope,
        value,
      );
    } else if (kind === "delete-section") {
      call("delete_section", sectionDeleteTarget);
    } else if (kind === "cleanup") {
      call(
        "remove_unused_definitions",
        cleanupTarget.map((item) => item.id),
      );
    } else if (kind === "delete-catalog") {
      if (
        !catalogDeleteTarget ||
        catalogDeleteTarget.scope !== "personal" ||
        !(state.catalog || []).some(
          (item) =>
            item.id === catalogDeleteTarget.id && item.scope === "personal",
        )
      ) {
        status("Удаление доступно только из личной библиотеки.", "error");
        closeModal();
        return;
      }
      call("delete_catalog_model", catalogDeleteTarget.id, "personal");
    } else if (kind.startsWith("decision-")) {
      call("set_maf_decision", ids, kind.slice(9));
    } else if (kind === "copy-selected") {
      if (!input) {
        status("Введите название копии.", "error");
        $("modal-input").focus();
        return;
      }
      call("copy_selected_to_library", value, input, $("modal-category").value);
    } else if (kind === "update-selected") {
      if (!selectedUpdateTarget?.previewToken) return;
      call("confirm_selected_card_update", selectedUpdateTarget.previewToken);
    } else if (kind === "update-version") {
      call(
        "update_catalog_version",
        versionTarget.id,
        $("modal-select-field").hidden ? null : value,
        versionTarget.scope,
      );
    } else if (kind === "rename") {
      if (!input) {
        status("Введите новое название модели.", "error");
        $("modal-input").focus();
        return;
      }
      call(
        "rename_rows",
        ids,
        input,
        $("modal-select-field").hidden ? "selected" : value,
      );
    } else if (kind === "create-section") {
      if (!input) {
        status("Введите название раздела.", "error");
        $("modal-input").focus();
        return;
      }
      call("create_section", input);
    } else if (kind === "section") {
      if (value === "__new__") {
        showModal("create-section", $("new-section"));
        return;
      }
      call("move_rows", ids, value);
    } else if (kind === "add-library") {
      call("add_rows_to_library", ids, value);
    } else if (kind === "delete") {
      call("delete_rows", ids);
    } else if (kind === "replace") {
      call("replace_rows", ids, value);
    } else if (kind === "duplicate") {
      call("replace_duplicates", duplicateGroup.id, value);
    }
    closeModal();
  }
  function catalogIdentity(element, id) {
    const key = element.closest("[data-card-key]")?.dataset.cardKey;
    return key || id;
  }
  function catalogItem(identity) {
    return (state.catalog || []).find((item) => `${item.scope}:${item.id}` === identity);
  }
  function imageData(file, id) {
    if (!file) return;
    if (file.size > 5000000) {
      status("Изображение больше 5 МБ. Выберите файл поменьше.", "error");
      return;
    }
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) {
      status("Поддерживаются PNG, JPEG и WebP.", "error");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      call("set_thumbnail", id, String(reader.result));
      if (modalKind === "paste") closeModal();
    };
    reader.onerror = () => status("Не удалось прочитать изображение.", "error");
    reader.readAsDataURL(file);
  }
  document.addEventListener("click", (event) => {
    const locate = event.target.closest(
      "[data-select-recognition],[data-focus-recognition]",
    );
    if (locate) {
      const id =
        locate.dataset.selectRecognition || locate.dataset.focusRecognition;
      if (
        !state.report_stale &&
        (state.models || []).some((row) => row.id === id)
      ) {
        if (locate.dataset.selectRecognition) {
          selectedNodeIds.clear();
          setSelection([id]);
        } else call("focus_rows", [id]);
      }
      return;
    }
    const placements = event.target.closest("[data-list-placements]");
    if (placements) {
      requestPlacements(placements.dataset.listPlacements, 0);
      return;
    }
    const placementPage = event.target.closest("[data-placement-offset]");
    if (placementPage) {
      requestPlacements(
        placementDefinition,
        Number(placementPage.dataset.placementOffset),
      );
      return;
    }
    const placementFocus = event.target.closest(
      "[data-focus-placement],[data-placement-choice]",
    );
    if (placementFocus) {
      if (!state.report_stale && placementData)
        send(
          "focus_placement",
          placementFocus.dataset.focusPlacement || placementFocus.value,
          placementData.report_token,
        );
      return;
    }
    const innerPage = event.target.closest(
      "[data-definition-next],[data-definition-prev]",
    );
    if (innerPage) {
      const key =
        innerPage.dataset.definitionNext || innerPage.dataset.definitionPrev;
      definitionPages.set(
        key,
        Math.max(
          0,
          (definitionPages.get(key) || 0) +
            (innerPage.dataset.definitionNext ? 1 : -1),
        ),
      );
      const scroll = document.scrollingElement.scrollTop;
      render();
      document.scrollingElement.scrollTop = scroll;
      return;
    }
    const pairButton = event.target.closest("[data-ignore-group]");
    if (pairButton) {
      const selected = pairSelections.get(pairButton.dataset.ignoreGroup);
      if (!state.report_stale && selected && selected.size === 2)
        call(
          "set_duplicate_ignored",
          pairButton.dataset.ignoreGroupId,
          ...Array.from(selected),
          true,
        );
      return;
    }
    const ignored = event.target.closest("[data-ignore-pair]");
    if (ignored) {
      if (!state.report_stale)
        call(
          "set_duplicate_ignored",
          ...JSON.parse(ignored.dataset.ignorePair),
          duplicateScope !== "ignored",
        );
      return;
    }
    if (event.target.closest("#reset-ignored")) {
      if (!state.report_stale) call("reset_duplicate_ignored");
      return;
    }
    const changeSection = event.target.closest("[data-change-catalog-section]");
    if (changeSection) {
      const item = (state.catalog || []).find(
        (x) =>
          x.id === changeSection.dataset.changeCatalogSection &&
          x.scope === changeSection.dataset.changeCatalogScope,
      );
      if (item && item.scope !== "cloud") {
        catalogSectionTarget = {
          id: item.id,
          scope: item.scope,
          name: item.name,
          category: item.category,
        };
        showModal("catalog-section", changeSection);
      }
      return;
    }
    const layout = event.target.closest("[data-catalog-layout]");
    if (layout) {
      catalogLayout = layout.dataset.catalogLayout;
      try {
        localStorage.setItem("maf.catalog.layout", catalogLayout);
      } catch (error) {}
      renderCatalog();
      return;
    }
    const sectionDelete = event.target.closest("[data-delete-section]");
    if (sectionDelete) {
      sectionDeleteTarget = sectionDelete.dataset.deleteSection;
      showModal("delete-section", sectionDelete);
      return;
    }
    const preview = event.target.closest("[data-load-previews]");
    if (preview) {
      const ids = JSON.parse(preview.dataset.previewIds);
      if (
        !send(
          "duplicate_previews",
          preview.dataset.loadPreviews,
          ids,
          String(previewEpoch),
        )
      ) {
        duplicatePreviews.set(
          previewKey(preview.dataset.loadPreviews, ids),
          {},
        );
        render();
        status("Демо: превью доступны в SketchUp.");
      }
      return;
    }
    const remove = event.target.closest("[data-delete-catalog]");
    if (remove) {
      const item = (state.catalog || []).find(
        (x) =>
          x.id === remove.dataset.deleteCatalog &&
          x.scope === remove.dataset.deleteScope,
      );
      if (item && item.scope === "personal") {
        catalogDeleteTarget = {
          id: item.id,
          scope: item.scope,
          name: item.name,
        };
        showModal("delete-catalog", remove);
      }
      return;
    }
    const view = event.target.closest("[data-catalog-view]");
    if (view) {
      $("catalog-view").value = view.dataset.catalogView;
      pageOffsets.catalog = 0;
      renderCatalog();
      return;
    }
    const paging = event.target.closest("[data-page-next],[data-page-prev]");
    if (paging) {
      const kind = paging.dataset.pageNext || paging.dataset.pagePrev;
      pageOffsets[kind] = Math.max(
        0,
        (pageOffsets[kind] || 0) + (paging.dataset.pageNext ? 1 : -1),
      );
      render();
      const pager = $("pager-" + kind);
      if (pager)
        pager.scrollIntoView({
          block: "nearest",
        });
      return;
    }
    const toggle = event.target.closest("[data-toggle-node]");
    if (toggle) {
      const id = toggle.dataset.toggleNode;
      collapsedNodes.has(id)
        ? collapsedNodes.delete(id)
        : collapsedNodes.add(id);
      renderModels();
      document.querySelectorAll("[data-toggle-node]").forEach((button) => {
        if (button.dataset.toggleNode === id) button.focus();
      });
      return;
    }
    const decision = event.target.closest("[data-decision]");
    if (decision) {
      selectedNodeIds.clear();
      setSelection([decision.dataset.decisionRow], false);
      showModal("decision-" + decision.dataset.decision, decision);
      return;
    }
    const selectedUpdate = event.target.closest("[data-update-selected]");
    if (selectedUpdate) {
      selectedUpdateTarget = {id: selectedUpdate.dataset.updateSelected, scope: selectedUpdate.dataset.updateScope, token: String(++selectedUpdateRequest)};
      showModal("update-selected", selectedUpdate);
      return;
    }
    const update = event.target.closest("[data-update-version]");
    if (update) {
      versionTarget = {
        id: update.dataset.updateVersion,
        scope: update.dataset.updateScope,
      };
      showModal("update-version", update);
      return;
    }
    if (event.target.closest("#retry-catalog-sync")) {
      closeSyncWarnings();
      $("scan").click();
      return;
    }
    const page = event.target.closest("[data-page]");
    if (page) {
      setPage(page.dataset.page);
      return;
    }
    const duplicateScopeButton = event.target.closest("[data-duplicate-scope]");
    if (duplicateScopeButton) {
      duplicateScope = duplicateScopeButton.dataset.duplicateScope;
      duplicateSelection.clear();
      pageOffsets.duplicates = 0;
      $("duplicate-owner").value = "";
      render();
      return;
    }
    const row = event.target.closest(".model-row");
    if (row) {
      selectRow(row, event);
      return;
    }
    const section = event.target.closest("[data-open-section]");
    if (section) {
      setPage("overview");
      $("model-section").value = section.dataset.openSection;
      renderModels();
      return;
    }
    const manual = event.target.closest("[data-manual-duplicate]");
    if (manual) {
      if (manual.disabled) return;
      showModal(
        "manual-duplicate",
        manual,
        duplicateItems().find(
          (x) => String(x.id) === manual.dataset.manualDuplicate,
        ),
      );
      return;
    }
    const group = event.target.closest("[data-duplicate]");
    if (group) {
      showModal(
        "duplicate",
        group,
        duplicateItems().find((x) => String(x.id) === group.dataset.duplicate),
      );
      return;
    }
    const favorite = event.target.closest("[data-favorite]");
    if (favorite) {
      const identity = catalogIdentity(favorite, favorite.dataset.favorite);
      const item = catalogItem(identity);
      if (item) {
        item.favorite = !item.favorite;
        call("update_catalog_details", identity, item.tags || [], item.favorite);
        renderCatalog();
      }
      return;
    }
    const tags = event.target.closest("[data-tags]");
    if (tags) {
      const identity = catalogIdentity(tags, tags.dataset.tags);
      const item = catalogItem(identity);
      if (item) {
        const answer = prompt(
          "Теги через запятую",
          Array.isArray(item.tags) ? item.tags.join(", ") : "",
        );
        if (answer !== null) {
          item.tags = answer
            .split(",")
            .map((x) => x.trim().toLowerCase())
            .filter(Boolean);
          call("update_catalog_details", identity, item.tags, !!item.favorite);
          renderCatalog();
        }
      }
      return;
    }
    const array = event.target.closest("[data-array]");
    if (array) {
      if (array.dataset.mode === "surface") {
        const density = prompt("Плотность: моделей на 1 м² (0.01–100)", "1");
        if (density === null) return;
        const setback = prompt("Отступ от границы, мм (0–10000)", "0");
        if (setback === null) return;
        const rotation = prompt("Случайный поворот ±градусов (0–180)", "0");
        if (rotation === null) return;
        const seed = prompt(
          "Seed для повторяемой раскладки (целое число)",
          "0",
        );
        if (seed === null) return;
        const options = {
          density: Number(density),
          setback_mm: Number(setback),
          rotation_degrees: Number(rotation),
          seed: Number(seed),
        };
        if (
          !Number.isFinite(options.density) ||
          options.density < 0.01 ||
          options.density > 100 ||
          !Number.isFinite(options.setback_mm) ||
          options.setback_mm < 0 ||
          options.setback_mm > 10000 ||
          !Number.isFinite(options.rotation_degrees) ||
          options.rotation_degrees < 0 ||
          options.rotation_degrees > 180 ||
          !Number.isInteger(options.seed)
        ) {
          status("Проверьте плотность, отступ, поворот и seed.", "error");
          return;
        }
        call("start_array", catalogIdentity(array, array.dataset.array), "surface", 1000, options);
      } else {
        const answer = prompt("Шаг в миллиметрах (100–10000)", "1000");
        if (answer !== null) {
          const value = Number(answer);
          if (!Number.isFinite(value) || value < 100 || value > 10000)
            status("Шаг должен быть от 100 до 10000 мм.", "error");
          else call("start_array", catalogIdentity(array, array.dataset.array), "line", value);
        }
      }
      return;
    }
    const place = event.target.closest("[data-place]");
    if (place) {
      call("place_model", catalogIdentity(place, place.dataset.place));
      return;
    }
    const auto = event.target.closest("[data-thumb-auto]");
    if (auto) {
      const job = previewJobs.get(catalogIdentity(auto, auto.dataset.thumbAuto));
      if (job && ["queued", "running"].includes(job.state)) call("cancel_preview", job.request_id);
      else call("regenerate_thumbnail", catalogIdentity(auto, auto.dataset.thumbAuto));
      return;
    }
    const file = event.target.closest("[data-thumb-file]");
    if (file) {
      imageTarget = catalogIdentity(file, file.dataset.thumbFile);
      $("image-file").value = "";
      $("image-file").click();
      return;
    }
    const paste = event.target.closest("[data-thumb-paste]");
    if (paste) {
      imageTarget = catalogIdentity(paste, paste.dataset.thumbPaste);
      showModal("paste", paste);
      return;
    }
    const choose = event.target.closest("[data-choose-path]");
    if (choose) {
      call("choose_library_path", choose.dataset.choosePath);
      return;
    }
    if (!$("context-menu").contains(event.target)) closeMenu();
  });
  $("cleanup-list").addEventListener("change", (event) => {
    const input = event.target.closest("[data-cleanup-id]");
    if (!input) return;
    input.checked
      ? cleanupSelection.add(input.dataset.cleanupId)
      : cleanupSelection.delete(input.dataset.cleanupId);
    $("cleanup-selected").disabled =
      !!state.report_stale || cleanupSelection.size === 0;
  });
  $("cleanup-selected").addEventListener("click", (event) => {
    cleanupTarget = ((state.cleanup || {}).unused_items || [])
      .filter((item) => cleanupSelection.has(String(item.id)))
      .map((item) => ({
        id: String(item.id),
        name: item.name,
      }));
    if (cleanupTarget.length && !state.report_stale)
      showModal("cleanup", event.target);
  });
  $("batch-preview").addEventListener("click", () => {
    if (batchSelection.size && !state.report_stale)
      showModal("batch-manual", $("batch-preview"));
  });
  $("batch-reset").addEventListener("click", () => {
    resetBatch();
    render();
  });
  $("duplicates-list").addEventListener("change", (event) => {
    const target = event.target.closest("[data-batch-target]");
    if (!target || target.disabled) return;
    batchTargets.set(target.dataset.batchTarget, target.value);
    const entry = batchSelection.get(target.dataset.batchTarget);
    if (entry) entry.target_id = target.value;
    invalidateBatch();
  });
  $("duplicates-list").addEventListener("click", (event) => {
    const button = event.target.closest("[data-batch-toggle]");
    if (!button || button.disabled) return;
    const key = button.dataset.batchToggle;
    if (batchSelection.has(key)) batchSelection.delete(key);
    else {
      const select = button
        .closest(".duplicate")
        .querySelector("[data-batch-target]");
      batchSelection.set(key, {
        group_id: key,
        target_id: select.value,
      });
    }
    invalidateBatch();
    render();
  });
  $("merge-nested").addEventListener("click", () => {
    if (state.report_stale || !$("duplicate-owner").value) return;
    nestedMergeOwner = $("duplicate-owner").value;
    showModal("nested-merge", $("merge-nested"));
  });
  $("duplicate-owner").addEventListener("change", () => {
    duplicateSelection.clear();
    pageOffsets.duplicates = 0;
    render();
  });
  $("duplicates-list").addEventListener("change", (event) => {
    const input = event.target.closest("[data-duplicate-choice]");
    if (!input) return;
    const key = input.dataset.pairGroup;
    if (key) {
      const pair = pairSelections.get(key) || new Set();
      input.checked ? pair.add(input.value) : pair.delete(input.value);
      pairSelections.set(key, pair);
    }
    input.checked
      ? duplicateSelection.add(input.value)
      : duplicateSelection.delete(input.value);
    render();
  });
  $("duplicates-list").addEventListener("click", (event) => {
    const button = event.target.closest("[data-focus-duplicate]");
    if (!button) return;
    const group = focusGroups.get(button.dataset.focusDuplicate);
    if (group && !state.report_stale)
      call(
        "focus_duplicates",
        group.definitions.map((item) => item.id),
      );
  });
  $("focus-duplicates").addEventListener("click", () =>
    call("focus_duplicates", Array.from(duplicateSelection)),
  );
  let copiedCatalogCard = null;
  let catalogMenu = null;
  function closeCatalogMenu(restore = false) {
    if (!catalogMenu) return;
    const trigger = catalogMenu.trigger;
    catalogMenu.remove(); catalogMenu = null;
    if (restore && trigger && trigger.isConnected) trigger.focus();
  }
  function openCatalogMenu(event) {
    const card = event.target.closest('.catalog-card');

    if (event.target.closest('input,textarea,select,[contenteditable="true"]')) return;
    event.preventDefault(); closeMenu(); closeCatalogMenu();
    const menu = document.createElement('div');
    menu.tabIndex = -1; menu.className = 'catalog-context-menu'; menu.setAttribute('role', 'menu');
    menu.setAttribute('aria-label', 'Действия с карточкой'); menu.trigger = card || $('catalog-list');
    function action(label, callback, disabled = false) {
      const button = document.createElement('button'); button.type = 'button';
      button.setAttribute('role', 'menuitem'); button.textContent = label; button.disabled = disabled;
      button.onclick = () => { closeCatalogMenu(true); callback(); };
      if (label.includes('Удалить')) button.className = 'catalog-context-danger';
      menu.appendChild(button);
    }
    if (card) {
      const item = (state.catalog || []).find(x => x.scope + ':' + x.id === card.dataset.cardKey);
      if (!item) return;
      const heading = document.createElement('div'); heading.className = 'catalog-context-heading'; heading.textContent = item.name; menu.appendChild(heading);
      for (const selector of ['[data-place]','[data-array][data-mode="line"]','[data-array][data-mode="surface"]','[data-favorite]','[data-change-catalog-section]','[data-tags]','[data-thumb-auto]','[data-thumb-file]','[data-update-version]','[data-update-selected]']) {
        const control = card.querySelector(selector);
        if (control) action(selector === '[data-favorite]' ? (item.favorite ? 'Убрать из избранного' : 'В избранное') : selector === '[data-thumb-auto]' ? 'Создать превью' : selector === '[data-thumb-file]' ? 'Выбрать изображение…' : control.textContent.trim(), () => control.click(), control.disabled);
      }
      menu.appendChild(document.createElement('hr'));
      action('Копировать карточку', () => { copiedCatalogCard = {id:item.id, scope:item.scope}; status('Карточка «' + item.name + '» скопирована'); });
    }
    if (!card && !copiedCatalogCard) action('Сначала скопируйте карточку', () => {}, true);
    if (copiedCatalogCard) {
      action('Вставить в модель', () => call('place_model', copiedCatalogCard.scope + ':' + copiedCatalogCard.id));
      const scope = $('catalog-scope').value;
      for (const destination of ['personal','shared']) {
        if (scope && scope !== 'all' && scope !== destination) continue;
        action(destination === 'personal' ? 'Вставить в личную библиотеку' : 'Вставить в общую библиотеку', () => {
          const category = $('category').value;
          call('copy_catalog_model', copiedCatalogCard.scope, copiedCatalogCard.id, destination, category && category !== 'all' ? category : null);
        });
      }
      if (scope === 'cloud') action('Вставка в облако недоступна', () => {}, true);
    }
    if (card) {
      const remove = card.querySelector('[data-delete-catalog]');
      if (remove) { menu.appendChild(document.createElement('hr')); action(remove.textContent.trim(), () => remove.click(), remove.disabled); }
    }
    document.body.appendChild(menu); catalogMenu = menu;
    const rect = (card || $("catalog-list")).getBoundingClientRect();
    const x = event.type === 'keydown' ? rect.left : event.clientX;
    const y = event.type === 'keydown' ? rect.bottom : event.clientY;
    menu.style.left = Math.max(8, Math.min(x, innerWidth - menu.offsetWidth - 8)) + 'px';
    menu.style.top = Math.max(8, Math.min(y, innerHeight - menu.offsetHeight - 8)) + 'px';
    (menu.querySelector('button:not(:disabled)') || menu).focus({preventScroll:true});
    menu.onkeydown = e => {
      const buttons = [...menu.querySelectorAll('button:not(:disabled)')];
      const index = buttons.indexOf(document.activeElement);
      if (['ArrowDown','ArrowUp','Home','End'].includes(e.key)) {
        e.preventDefault(); buttons[e.key === 'Home' ? 0 : e.key === 'End' ? buttons.length - 1 : (index + (e.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length]?.focus();
      } else if (e.key === 'Escape') { e.preventDefault(); closeCatalogMenu(true); }
      else if (e.key === 'Tab') closeCatalogMenu(true);
    };
  }
  $('catalog-list').addEventListener('contextmenu', openCatalogMenu);
  $('catalog-list').addEventListener('keydown', event => {
    if (event.key === 'ContextMenu' || (event.shiftKey && event.key === 'F10')) openCatalogMenu(event);
  });
  document.addEventListener('pointerdown', e => { if (catalogMenu && !catalogMenu.contains(e.target)) closeCatalogMenu(); });
  document.addEventListener('scroll', e => { if (catalogMenu && !catalogMenu.contains(e.target)) closeCatalogMenu(); }, true);
  window.addEventListener('resize', () => closeCatalogMenu());

  $("models-body").addEventListener("contextmenu", (event) => {
    const row = event.target.closest(".model-row");
    if (!row) return;
    event.preventDefault();
    if (!selectedIds.has(row.dataset.row)) {
      selectedNodeIds = new Set([row.dataset.node]);
      setSelection([row.dataset.row]);
      anchorId = row.dataset.node;
    }
    openMenu(event.clientX, event.clientY, row);
  });
  $("models-body").addEventListener("keydown", (event) => {
    const row = event.target.closest(".model-row");
    if (!row) return;
    if (event.target.closest("[data-toggle-node]")) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      selectRow(row, event);
    } else if (
      event.key === "ContextMenu" ||
      (event.shiftKey && event.key === "F10")
    ) {
      event.preventDefault();
      if (!selectedIds.has(row.dataset.row)) setSelection([row.dataset.row]);
      const rect = row.getBoundingClientRect();
      openMenu(rect.left + 40, rect.top + 30, row);
    }
  });
  $("context-menu").addEventListener("click", (event) => {
    const action = event.target.closest("[data-action]");
    if (action) showModal(action.dataset.action, contextTrigger);
  });
  $("selected-menu").addEventListener("click", (event) => {
    event.stopPropagation();
    const rect = event.target.getBoundingClientRect();
    openMenu(rect.left, rect.bottom + 5, event.target);
  });
  $("clear-selection").addEventListener("click", () => {
    selectedNodeIds.clear();
    setSelection([]);
  });
  $("replace-selected").addEventListener("click", (event) => {
    if (selectedIds.size) showModal("replace", event.target);
    else if (!send("replace_selected"))
      status("Сначала выделите строки в списке или компоненты в SketchUp.");
  });
  $("export-report").addEventListener("click", () => call("export_report"));
  $("scan").addEventListener("click", () => {
    if (scanState !== "idle") return;
    syncWarningsAnalyzing = true;
    status("Анализ модели…");
    setScanState("running");
    if (demo) {
      demoScanTimer = setTimeout(() => {
        demoScanTimer = null;
        const seconds = (performance.now() - scanStartedAt) / 1000;
        state = clone(sample);
        selectedIds.clear();
        duplicateSelection.clear();
        render();
        setScanState("idle", seconds);
        status("Демо: анализ завершен.", "success");
      }, 250);
    } else if (!send("scan")) {
      setScanState("idle");
      status("Не удалось запустить анализ.", "error");
    }
  });
  $("stop-scan").addEventListener("click", () => {
    if (scanState !== "running") return;
    setScanState("stopping");
    if (demo) {
      if (demoScanTimer) clearTimeout(demoScanTimer);
      demoScanTimer = null;
      setTimeout(() => setScanState("idle"), 100);
    } else if (!send("cancel_scan")) {
      setScanState("running", null, true);
      status("Не удалось отправить запрос на остановку.", "error");
    }
  });
  $("add-selected").addEventListener("click", () =>
    call("add_selected_to_library", $("import-scope").value),
  );
  $("copy-selected").addEventListener("click", (event) =>
    showModal("copy-selected", event.target),
  );
  $("maf-filter").addEventListener("change", renderModels);
  $("import").addEventListener("click", () => {
    if (!send("import_model", $("import-scope").value))
      status("Добавление .skp доступно в установленном расширении SketchUp.");
  });
  $("scan-catalog").addEventListener("click", () =>
    call("scan_catalog", $("import-scope").value),
  );
  $("export-pack").addEventListener("click", () => {
    const scope = $("import-scope").value;
    const ids = Array.from(
      document.querySelectorAll("#catalog-list [data-place]"),
    )
      .map((button) => button.dataset.place)
      .filter((id) =>
        (state.catalog || []).some(
          (item) => item.id === id && item.scope === scope,
        ),
      );
    if (ids.length) call("export_pack", scope, ids);
    else status("Нет видимых моделей выбранной библиотеки.", "error");
  });
  $("import-pack").addEventListener("click", () =>
    call("import_pack", $("import-scope").value),
  );
  $("new-section").addEventListener("click", (event) =>
    showModal("create-section", event.target),
  );
  const catalogFilter = () => {
    pageOffsets.catalog = 0;
    renderCatalog();
  };
  $("search").addEventListener("input", catalogFilter);
  $("category").addEventListener("change", catalogFilter);
  $("catalog-scope").addEventListener("change", catalogFilter);
  $("catalog-view").addEventListener("change", catalogFilter);
  $("model-section").addEventListener("change", () => {
    pageOffsets.models = 0;
    renderModels();
  });
  $("manual-accept").addEventListener("change", updateManualConfirmation);
  $("modal-select").addEventListener("change", () => {
    if (modalKind === "manual-duplicate") requestManualReplacementPreview();
    if (modalKind === "replace" || modalKind === "duplicate")
      requestReplacementPreview();
    if (modalKind === "rename" && !actionInvalidated) {
      const selected = (state.models || []).filter((row) =>
        modalIds.includes(row.id),
      );
      const match = (state.duplicates || []).find((group) =>
        selected.some((row) =>
          group.definitions.some((def) => row.definition_ids.includes(def.id)),
        ),
      );
      const rows =
        $("modal-select").value === "selected" || !match
          ? selected
          : (state.models || []).filter((row) =>
              match.definitions.some((def) =>
                row.definition_ids.includes(def.id),
              ),
            );
      renderGlobalScope(rows);
    }
  });
  $("save-cloud").addEventListener("click", () =>
    call("set_cloud_url", $("cloud-url").value.trim()),
  );
  $("sync-cloud").addEventListener("click", () => {
    if (!send("sync_cloud"))
      status("Синхронизация облака выполняется в SketchUp.");
  });
  $("check-update").addEventListener("click", () => {
    status("Проверка GitHub Releases…");
    if (!send("check_update"))
      status("Демо: проверка обновлений выполняется в SketchUp.");
  });
  $("install-update").addEventListener("click", () => send("install_update"));
  $("image-file").addEventListener("change", (event) =>
    imageData(event.target.files[0], imageTarget),
  );
  $("paste-zone").addEventListener("paste", (event) => {
    const item = Array.from(event.clipboardData.items || []).find(
      (x) => x.type.indexOf("image/") === 0,
    );
    if (!item) {
      status(
        "В буфере нет изображения. Скопируйте снимок и попробуйте снова.",
        "error",
      );
      return;
    }
    event.preventDefault();
    imageData(item.getAsFile(), imageTarget);
  });
  $("cancel").addEventListener("click", closeModal);
  $("confirm").addEventListener("click", submitModal);
  $("modal-backdrop").addEventListener("click", (event) => {
    if (event.target === $("modal-backdrop")) closeModal();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      if ($("modal-backdrop").classList.contains("open")) closeModal();
      else closeMenu();
    }
    if (event.key === "Tab" && $("modal-backdrop").classList.contains("open")) {
      const nodes = Array.from(
        $("modal-backdrop").querySelectorAll(
          "button:not(:disabled):not([hidden]),input:not([hidden]),select:not([hidden]),[contenteditable]:not([hidden])",
        ),
      ).filter((x) => x.offsetParent !== null);
      const first = nodes[0],
        last = nodes[nodes.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape")
      document.querySelectorAll(".command-menu[open]").forEach((menu) => {
        menu.open = false;
        menu.querySelector("summary").focus();
      });
  });
  document.addEventListener("click", (event) => {
    document.querySelectorAll(".command-menu[open]").forEach((menu) => {
      if (!menu.contains(event.target)) menu.open = false;
    });
  });
  $("compact-catalog-scope").addEventListener("change", () => {
    $("catalog-scope").value = $("compact-catalog-scope").value;
    pageOffsets.catalog = 0;
    renderCatalog();
  });
  $("catalog-scope").addEventListener("change", () => {
    $("compact-catalog-scope").value = $("catalog-scope").value;
  });
  $("theme-toggle").addEventListener("click", () => {
    const current =
      document.documentElement.dataset.theme ||
      (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.dataset.theme =
      current === "dark" ? "light" : "dark";
  });
  window.MAF = {
    receive(payload) {
      const updatePreview = payload.selected_card_update_preview;
      if (updatePreview && modalKind === "update-selected" && selectedUpdateTarget && String(updatePreview.token) === selectedUpdateTarget.token && updatePreview.id === selectedUpdateTarget.id && updatePreview.scope === selectedUpdateTarget.scope) {
        selectedUpdateTarget.previewToken = updatePreview.error ? null : updatePreview.preview_token;
        $("confirm").disabled = !selectedUpdateTarget.previewToken;
        $("modal-status").hidden = !updatePreview.error;
        $("modal-status").textContent = updatePreview.error ? `${updatePreview.error} Закройте окно, исправьте выделение и повторите действие.` : "";
        $("modal-description").textContent = updatePreview.error || `Заменить содержимое карточки «${updatePreview.target_name}» из выделенного объекта «${updatePreview.source_name}»? Название, категория и теги сохранятся. Размещения в проекте останутся без изменений.`;
      }
      if (payload.preview_event) {
        const job = payload.preview_event, key = `${job.scope}:${job.id}`, old = previewJobs.get(key);
        if (!old || old.request_id === job.request_id || job.state === "queued" || job.request_id.startsWith("unavailable-")) {
          previewJobs.set(key, job);
          const card = payload.preview_card;
          if (job.state === "succeeded" && card && card.scope === job.scope && card.id === job.id) {
            state.catalog = (state.catalog || []).map(oldCard =>
              oldCard.scope === card.scope && oldCard.id === card.id ? {...oldCard, ...card} : oldCard);
          }
          renderCatalog();
        }
      }
      if (Object.prototype.hasOwnProperty.call(payload, "replacement_result")) {
        $("replacement-result").hidden = !payload.replacement_result;
        $("replacement-message").textContent = payload.replacement_result
          ? payload.replacement_result.message
          : "";
      }
      if (payload.data || payload.report_stale || payload.duplicate_decisions)
        resetBatch();
      if (payload.batch_manual_replacement_preview)
        renderBatchPreview(payload.batch_manual_replacement_preview);
      if (payload.duplicate_decisions) {
        const update = payload.duplicate_decisions;
        state = {
          ...state,
          duplicates: update.duplicates || [],
          other_duplicates: update.other_duplicates || [],
          nested_duplicates: update.nested_duplicates || [],
          ignored_duplicates: update.ignored_duplicates || [],
          summary: update.summary || state.summary,
        };
        pairSelections.clear();
        duplicateSelection.clear();
        duplicatePreviews.clear();
        previewEpoch++;
        if (
          modalKind === "duplicate" ||
          modalKind === "manual-duplicate" ||
          modalKind === "nested-merge"
        ) {
          actionInvalidated = true;
          $("confirm").disabled = true;
        }
        render();
      }
      if (
        payload.placements &&
        !state.report_stale &&
        String(payload.placements.request_token) === String(placementRequest) &&
        String(payload.placements.definition_id) === placementDefinition
      ) {
        placementData = payload.placements;
        patchPlacements();
      }
      if (
        (payload.report_stale || payload.data) &&
        modalKind &&
        (!$("action-scope").hidden ||
          modalKind === "update-version" ||
          modalKind === "cleanup" ||
          modalKind === "nested-merge")
      ) {
        actionInvalidated = true;
        $("confirm").disabled = true;
        $("action-scope").hidden = false;
        $("action-scope").textContent =
          "Отчёт устарел или обновлён. Закройте окно и откройте действие снова для проверки всех размещений.";
      }
      if (payload.manual_replacement_preview)
        renderManualReplacementPreview(payload.manual_replacement_preview);
      if (payload.replacement_preview)
        renderReplacementPreview(payload.replacement_preview);
      if (payload.nested_merge_preview)
        renderNestedMergePreview(payload.nested_merge_preview);
      if (payload.duplicate_previews) {
        const result = payload.duplicate_previews;
        if (
          !state.report_stale &&
          String(result.token) === String(previewEpoch)
        ) {
          duplicatePreviews.set(
            previewKey(result.group_id, result.ids || []),
            result.images || {},
          );
          if (activePage === "duplicates") patchDuplicatePreviews(result);
        }
      }
      const hasReportStale = Object.prototype.hasOwnProperty.call(
        payload,
        "report_stale",
      );
      if (payload.data) {
        previewEpoch++;
        pairSelections.clear();
        placementRequest++;
        placementData = null;
        placementDefinition = "";
        definitionPages.clear();
        state = payload.data;
        const nextWarnings = JSON.stringify((state.catalog_sync_errors || []).map(error => [error.row_id, error.message, error.code, ((state.models || []).find(row => row.id === error.row_id) || {}).name]));
        syncWarningsPending = !!(state.catalog_sync_errors || []).length && (syncWarningsPending || syncWarningsAnalyzing || nextWarnings !== syncWarningsSignature);
        syncWarningsAnalyzing = false;
        pageOffsets = {};
        duplicateSelection.clear();
        cleanupSelection.clear();
        duplicatePreviews.clear();
        const valid = new Set((state.models || []).map((row) => row.id));
        selectedIds = new Set(
          Array.from(selectedIds).filter((id) => valid.has(id)),
        );
      }
      if (payload.catalog_card_update) {
        const card = payload.catalog_card_update;
        state = {...state, catalog: (state.catalog || []).map((old) =>
          old.scope === card.scope && old.id === card.id ? {...old, ...card} : old)};
      }
      if (payload.catalog_update) {
        const update = payload.catalog_update;
        if (update.catalog) {
          const old = new Map(
            (state.catalog || []).map((card) => [
              card.scope + ":" + card.id,
              card,
            ]),
          );
          update.catalog = update.catalog.map((card) => ({
            ...old.get(card.scope + ":" + card.id),
            ...card,
          }));
        }
        state = {
          ...state,
          ...update,
        };
      }
      if (hasReportStale) {
        state.report_stale = payload.report_stale;
        if (payload.report_stale) {
          previewEpoch++;
          duplicatePreviews.clear();
          cleanupSelection.clear();
          duplicateSelection.clear();
          if (activePage === "cleanup") renderCleanup();
          if (activePage === "duplicates") render();
        }
      }
      if (payload.data || payload.catalog_update || payload.catalog_card_update) render();
      else if (hasReportStale) renderReportStaleOnly();
      if (payload.open_catalog_id) {
        setPage("catalog");
        $("search").value = "";
        $("category").value = "";
        $("catalog-view").value = "all";
        $("catalog-scope").value = payload.open_catalog_scope || "";
        const cards = (state.catalog || []).filter(
          (card) =>
            !payload.open_catalog_scope ||
            card.scope === payload.open_catalog_scope,
        );
        pageOffsets.catalog = Math.max(
          0,
          Math.floor(
            cards.findIndex((card) => card.id === payload.open_catalog_id) /
              pageSize,
          ),
        );
        renderCatalog();
        document.querySelectorAll("[data-card-key]").forEach((card) => {
          if (
            card.dataset.cardKey ===
            payload.open_catalog_scope + ":" + payload.open_catalog_id
          ) {
            card.focus();
            card.scrollIntoView({
              block: "nearest",
            });
          }
        });
      }
      if (payload.recognition_warnings && payload.recognition_warnings.length)
        status(
          payload.recognition_warnings.map(warningLabel).join(" · "),
          "error",
        );
      if (payload.selected_rows) {
        if (
          payload.selected_rows.length !== selectedIds.size ||
          payload.selected_rows.some((id) => !selectedIds.has(id))
        )
          selectedNodeIds.clear();
        selectedIds = new Set(payload.selected_rows);
        renderSelection();
      }
      if (payload.scan_state === "idle" && !payload.data) syncWarningsAnalyzing = false;
      if (payload.scan_state)
        setScanState(
          payload.scan_state,
          Object.prototype.hasOwnProperty.call(payload, "analysis_seconds")
            ? payload.analysis_seconds
            : null,
        );
      else if (
        Object.prototype.hasOwnProperty.call(payload, "analysis_seconds")
      )
        setScanState("idle", payload.analysis_seconds);
      if (payload.message)
        status(
          payload.message +
            (payload.recognition_warnings && payload.recognition_warnings.length
              ? " · " +
                payload.recognition_warnings.map(warningLabel).join(" · ")
              : ""),
          payload.error ||
            (payload.recognition_warnings &&
              payload.recognition_warnings.length)
            ? "error"
            : "success",
        );
      renderReplacementResult();
      if (payload.mode) $("mode-label").textContent = payload.mode;
      if (Object.prototype.hasOwnProperty.call(payload, "update")) {
        pendingUpdate = payload.update;
        $("install-update").hidden = !pendingUpdate;
        $("update-message").textContent = pendingUpdate
          ? `Доступна версия ${pendingUpdate.version}. Установка потребует подтверждения SketchUp.`
          : "Новых опубликованных версий нет.";
      }
    },
  };
  render();
  setPage("catalog");
  if (!demo) {
    $("mode-label").textContent = "ОТКРЫТЫЙ ПРОЕКТ · SKETCHUP";
    send("ready");
  }
}
