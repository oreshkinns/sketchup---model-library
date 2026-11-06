import React from "react";

export function DuplicateActions({
  defs,
  group,
  groupKey,
  selected,
  state,
  target,
  unsupported,
  viewList,
}) {
  return (
    <div className={"duplicate-actions"}>
      <label>
        {"Эталон для пакета "}
        <select
          data-batch-target={groupKey}
          aria-label={"Эталон для пакета: " + group.label}
          {...(state.report_stale || unsupported
            ? {
                disabled: true,
              }
            : {})}
        >
          {viewList(
            defs.map((d) => (
              <option
                value={d.id}
                {...(String(d.id) === target
                  ? {
                      selected: true,
                    }
                  : {})}
              >
                {d.name}
              </option>
            )),
          )}
        </select>
      </label>
      <button
        className={"button small"}
        data-batch-toggle={groupKey}
        {...(state.report_stale || unsupported
          ? {
              disabled: true,
            }
          : {})}
      >
        {selected ? "Убрать из пакета" : "Добавить в пакет"}
      </button>
      {unsupported ? (
        <span className={"hint"}>
          {"Для пакета нужны два определения; исключения не поддерживаются."}
        </span>
      ) : (
        ""
      )}
    </div>
  );
}

export function ModelTreeRow({
  actionable,
  children,
  depth,
  identity,
  node,
  open,
  row,
  valueOr,
}) {
  return (
    <tr
      data-node={node.id}
      {...(actionable
        ? {
            className: "model-row",
            tabIndex: "0",
            "aria-selected": "false",
            "data-row": row.id,
          }
        : {
            className: "tree-container",
          })}
    >
      <td>
        <div
          className={"tree-label"}
          style={{
            paddingLeft: depth * 18 + "px",
          }}
        >
          {children.length ? (
            <button
              className={"tree-toggle"}
              data-toggle-node={node.id}
              aria-expanded={open}
              aria-label={(open ? "Свернуть" : "Развернуть") + " " + node.name}
            ></button>
          ) : (
            <span className={"tree-spacer"}></span>
          )}
          <div>
            <span className={"model-name"}>{node.name}</span>
            <span className={"sub"}>{identity}</span>
          </div>
        </div>
      </td>
      <td>{(row && row.category) || "—"}</td>
      <td className={"mono"} data-branch-count={""}>
        {valueOr(node.instances, 0)}
      </td>
      <td className={"mono"}>{valueOr(row && row.definitions, "—")}</td>
      <td>
        {row && row.recognition_warnings && row.recognition_warnings.length ? (
          <span className={"badge warn"}>{"Проверить"}</span>
        ) : node.is_maf ? (
          <span className={"badge"}>{"МАФ"}</span>
        ) : (
          "—"
        )}
      </td>
    </tr>
  );
}

export function RecognitionCard({
  candidate,
  dimensions,
  geometryText,
  m,
  reasonLabel,
  row,
  sourceLabel,
  state,
  valueOr,
  viewList,
  warningLabel,
}) {
  return (
    <details
      className={"recognition-item"}
      {...(candidate
        ? {
            open: true,
          }
        : {})}
      {...(candidate
        ? {
            "data-candidate": row.id,
          }
        : {})}
    >
      <summary>
        {row.name}
        {" · "}
        {row.is_maf ? "МАФ" : candidate ? "Кандидат" : "Другая модель"}
      </summary>
      <p className={"hint"}>
        {"Источник: "}
        {sourceLabel(row.recognition_source)}
      </p>
      <p className={"hint"} data-reason={""}>
        {"Причина: "}
        {reasonLabel(row.recognition_reason)}
      </p>
      <p className={"catalog-warning"} data-warnings={""}>
        {(row.recognition_warnings || []).map(warningLabel).join(" · ")}
      </p>
      <div className={"parameters"}>
        <div>
          {"Имена: "}
          {(row.names || [row.name]).join(", ")}
          <br></br>
          {"Раздел: "}
          {row.category || "—"}
          <br></br>
          {"Теги: "}
          {(row.tags || []).join(", ") || "—"}
        </div>
        <div>
          {"Габариты: "}
          {dimensions(m)}
          <br></br>
          {geometryText(m)}
          <br></br>
          {"Вложенность: "}
          {valueOr(m.nesting_depth, "—")}
        </div>
        <div>
          {"Особенности: "}
          {Object.entries(m.behavior_flags || {})
            .map(
              ([k, v]) =>
                k + ": " + (v === true ? "да" : v === false ? "нет" : v),
            )
            .join(", ") || "—"}
        </div>
        <div>
          {"Атрибуты: "}
          {Object.entries(m.extension_attributes || {})
            .map(
              ([k, v]) =>
                k + ": " + (typeof v === "object" ? JSON.stringify(v) : v),
            )
            .join(", ") || "—"}
        </div>
      </div>
      <div className={"row-actions"}>
        <button
          className={"button small"}
          data-select-recognition={row.id}
          {...(state.report_stale
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Выбрать в модели"}
        </button>
        <button
          className={"button small"}
          data-focus-recognition={row.id}
          {...(state.report_stale
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Показать в модели"}
        </button>
      </div>
      <div className={"row-actions"}>
        {viewList(
          [
            ["confirmed", "Подтвердить МАФ"],
            ["rejected", "Не МАФ"],
            ["clear", "Сбросить решение"],
          ].map(([value, label]) => (
            <button
              className={"button small"}
              data-decision={value}
              data-decision-row={row.id}
            >
              {label}
              {" · все размещения"}
            </button>
          )),
        )}
      </div>
    </details>
  );
}

export function CatalogCard({
  count,
  linked,
  meta,
  scopeName,
  sourceLabel,
  tags,
  valueOr,
  warningLabel,
  warnings,
  x,
}) {
  return (
    <article
      className={"catalog-card"}
      tabIndex={"0"}
      data-card-key={x.scope + ":" + x.id}
    >
      <div className={"catalog-art"}>
        {x.thumbnail ? (
          <img src={x.thumbnail} alt={"Миниатюра: " + x.name}></img>
        ) : (
          <span aria-label={"Нет миниатюры"}>{"◫"}</span>
        )}
      </div>
      <div className={"catalog-copy"}>
        <h3>{x.name}</h3>
              {x.previewJob && <p role="status">{({queued: "Превью в очереди", running: "Создание превью", failed: x.previewJob.error || "Ошибка превью", cancelled: "Превью отменено"})[x.previewJob.state]}</p>}
        <div className={"scope-tag"}>
          {x.category || "Другое"}
          {" · "}
          {scopeName(x.scope)}
        </div>
        <p data-placement-count={""}>
          {"В текущем проекте: "}
          {count}
        </p>
        {warnings.length ? (
          <div className={"catalog-warning"}>
            {warnings.map(warningLabel).join(" · ")}
          </div>
        ) : (
          ""
        )}
      </div>
      <div className={"row-actions"}>
        <button className={"button small primary"} data-place={x.id}>
          {"Разместить"}
        </button>
        <button
          className={"button small"}
          data-favorite={x.id}
          aria-label={"Избранное"}
        >
          {x.favorite ? "★" : "☆"}
        </button>
      </div>
      <details className={"catalog-more"}>
        <summary>{"Подробнее"}</summary>
        <div className={"catalog-details"}>
          <div className={"catalog-meta"}>{meta}</div>
          <div className={"catalog-meta"}>
            {"Версия: "}
            {valueOr(x.version, "—")}
            {" · Источник: "}
            {sourceLabel(x.recognition_source)}
          </div>
          <details className={"catalog-more checksum"}>
            <summary>{"Контрольная сумма SHA-256"}</summary>
            {x.sha256 || "—"}
          </details>
          <div className={"catalog-tags"}>
            {tags.map((tag) => "#" + tag).join(" ")}
          </div>
          <div className={"row-actions"}>
            <button
              className={"button small"}
              data-array={x.id}
              data-mode={"line"}
            >
              {"По линии"}
            </button>
            <button
              className={"button small"}
              data-array={x.id}
              data-mode={"surface"}
            >
              {"По поверхности"}
            </button>
          </div>
          {x.scope === "cloud" ? (
            ""
          ) : (
            <>
              <button className={"button small"} data-update-selected={x.id} data-update-scope={x.scope}>{"Обновить из выделенного…"}</button>
              {linked.length || warnings.length ? (
                <button
                  className={"button small"}
                  data-update-version={x.id}
                  data-update-scope={x.scope}
                >
                  {"Обновить версию…"}
                </button>
              ) : (
                ""
              )}
              <div className={"row-actions"}>
                <button className={"button small"} data-tags={x.id}>
                  {"Теги"}
                </button>
                <button className={"button small"} data-thumb-auto={x.id}>
                  {x.previewJob && ["queued", "running"].includes(x.previewJob.state) ? "Отменить превью" : x.previewJob?.state === "failed" ? "Повторить превью" : "Создать превью"}
                </button>
                <button className={"button small"} data-thumb-file={x.id}>
                  {"Файл"}
                </button>
                <button className={"button small"} data-thumb-paste={x.id}>
                  {"Буфер"}
                </button>
              </div>
              <button
                className={"button small"}
                data-change-catalog-section={x.id}
                data-change-catalog-scope={x.scope}
              >
                {"Изменить раздел…"}
              </button>
              {x.scope === "personal" ? (
                <button
                  className={"button small danger"}
                  data-delete-catalog={x.id}
                  data-delete-scope={"personal"}
                >
                  {"Удалить из библиотеки…"}
                </button>
              ) : (
                <p className={"hint"}>
                  {"Удаление из общей библиотеки запрещено."}
                </p>
              )}
            </>
          )}
        </div>
      </details>
    </article>
  );
}

export function SectionRow({ library, project, section }) {
  return (
    <div className={"list-item"}>
      <div>
        <h3>{section}</h3>
        <p className={"hint"}>
          {"МАФ в проекте: "}
          {project}
          {" размещений · в библиотеках: "}
          {library}
          {" моделей"}
        </p>
      </div>
      <div className={"section-actions"}>
        <button className={"button small"} data-open-section={section}>
          {"Открыть"}
        </button>
        {section === "Другое" ? (
          ""
        ) : (
          <button
            className={"button small danger"}
            data-delete-section={section}
          >
            {"Удалить…"}
          </button>
        )}
      </div>
    </div>
  );
}

export function PlacementGroup({
  children,
  group,
  placementDefinition,
  state,
}) {
  return (
    <article className={"duplicate"}>
      <h3>{group.name}</h3>
      <p>
        {group.instances || 0}
        {" размещений одного определения"}
      </p>
      <button
        className={"button small"}
        data-list-placements={group.definition_id || group.id}
        {...(state.report_stale
          ? {
              disabled: true,
            }
          : {})}
      >
        {"Показать размещения"}
      </button>
      {placementDefinition === String(group.definition_id || group.id) ? (
        <div id={"placement-items"}>{children}</div>
      ) : (
        ""
      )}
    </article>
  );
}

export function CleanupRow({ cleanupSelection, item, stale }) {
  return (
    <label className={"list-item cleanup-choice"}>
      <input
        type={"checkbox"}
        data-cleanup-id={item.id}
        {...(cleanupSelection.has(String(item.id))
          ? {
              checked: true,
            }
          : {})}
        {...(stale
          ? {
              disabled: true,
            }
          : {})}
      ></input>
      <span>{item.name}</span>
    </label>
  );
}

export function DuplicateCard({
  batchControls,
  comparison,
  definitionKey,
  definitionPager,
  duplicateScope,
  focusGroupKey,
  group,
  ignoreControls,
  pairSelections,
  state,
  viewList,
  visibleDefinitions,
}) {
  return (
    <article className={"duplicate"}>
      <div className={"duplicate-title"}>
        <div>
          {group.owner_name ? (
            <p className={"duplicate-owner"}>
              {"МАФ: "}
              {group.owner_name}
            </p>
          ) : (
            ""
          )}
          <h3>{group.label}</h3>
        </div>
        <span className={"badge " + (group.replaceable === true ? "" : "warn")}>
          {{
            confirmed: "Подтвержденный дубль",
            candidate: "Кандидат",
            similar: "Сходные модели",
          }[group.classification] || "Кандидат"}
          {" · "}
          {group.definitions.length}
          {" определения"}
        </span>
      </div>
      <p>
        {group.confidence}
        {" · "}
        {group.definitions.reduce((a, d) => a + (d.instances || 0), 0)}
        {" размещений"}
        {Array.isArray(group.reasons) && group.reasons.length
          ? ` · ${group.reasons.join("; ")}`
          : ""}
      </p>
      {comparison(group)}
      {definitionPager(group)}
      {batchControls(group)}
      {ignoreControls(group)}
      <div className={"pill-row"}>
        {viewList(
          visibleDefinitions(group).map((d) => (
            <label className={"pill duplicate-choice"}>
              <input
                type={"checkbox"}
                data-duplicate-choice={""}
                data-pair-group={definitionKey(group)}
                value={d.id}
                {...((
                  pairSelections.get(definitionKey(group)) || new Set()
                ).has(String(d.id))
                  ? {
                      checked: true,
                    }
                  : {})}
                {...(state.report_stale || group.scope_conflict
                  ? {
                      disabled: true,
                    }
                  : {})}
              ></input>
              <span>
                {d.name}
                {" · "}
                {d.instances || 0}
              </span>
            </label>
          )),
        )}
      </div>
      <div>
        <button
          className={"button small"}
          data-duplicate={group.id}
          {...(state.report_stale ||
          group.replaceable !== true ||
          group.kind === "group"
            ? {
                disabled: true,
              }
            : {})}
        >
          {group.kind === "group"
            ? "Автозамена групп отключена"
            : group.replaceable !== true
              ? "Замена заблокирована"
              : "Проверить замену →"}
        </button>{" "}
        <button
          className={"button small"}
          data-manual-duplicate={group.id}
          {...(state.report_stale || duplicateScope === "ignored"
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Заменить на эталон…"}
        </button>{" "}
        <button
          className={"button small"}
          data-focus-duplicate={focusGroupKey(group)}
          {...(state.report_stale || group.scope_conflict
            ? {
                disabled: true,
              }
            : {})}
        >
          {"Сфокусироваться"}
        </button>
      </div>
    </article>
  );
}
