---
id: 93
date: 2026-06-11
title: "Kit v1.6.0: operator handoff footer"
tags: [canon, plugin, release, ux, d-cycle]
status: complete
---

# Kit v1.6.0: operator handoff footer

## Контекст
Discoverability-gap, два сигнала за день (multi-source → проходит gate D-цикла):
1. Battle-test на dialog_analyzer (watch в memory): audit-сессия не предложила
   operator-playbook как вход — оператор не узнал про /external-audit и Phase 5 kit.
2. Прямой операторский фидбек: «не понимаю, как полноценно использовать функционал;
   нужен небольшой readme при первом использовании».

Корень: машинерия kit'а opt-in by design (lazy-layer), поэтому из одного прогона
оператор её не открывает. Карта существует (operator-playbook.md), но ничто её не
показывает.

## Изменение
SKILL.md — новая секция «Operator handoff»: каждый прогон Bootstrap/Audit (и первое
использование скилла в проекте) завершается компактной операторской картой-футером —
5 строк фраз-триггеров (audit / bootstrap / Phase 5 kit / external-audit / указатель на
operator-playbook). Явные ограничители: «footer, not a lecture», skip если оператор
очевидно знает kit. Механизм — инструкция в теле скилла (носитель уже загружен в момент
нужды; hook/README были бы лишним слоем — README не самопоказывается, hook = машинерия).

## Verify
Plugin/marketplace = 1.6.0, JSON валидны, tag `claude-code-harness--v1.6.0`.
Watch из памяти battle-test закрыт fold'ом. Проверка эффекта — следующий
Bootstrap/Audit прогон на реальном проекте: футер должен появиться без напоминания.
