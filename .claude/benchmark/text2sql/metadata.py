"""
Модуль для хранения метаданных таблиц базы данных.
Содержит описание структуры таблиц, их полей и назначения.
"""

from typing import Any

# Метаданные таблицы client_product
ALL_CLI_METADATA = {
    "table_name": "client_product",
    "description": """
    Таблица содержит статистическую информацию по клиенту за каждый отчетный месяц.
    Поле month_dt - указывает на отчетный месяц, содержит последнюю дату отчетного месяца.
    Каждая строка - это значение показателя за месяц для одного клиента.

    ВАЖНО: Поля с суммами и количеством - это сумма и количество по операциям, сумма дохода за месяц.
    Накопительных сумм за период в таблице НЕТ.

    Детализации счетов до клиента в этой таблице нет. Все значения агрегированы до клиента.

    Таблица содержит информацию по клиентам корпоративного бизнеса: сегменты крупнго и среднего бизнеса.
    Если вопрос относится к корпоративным клиентам, корпоративному бизнесу, то никакие дополнительные фильтры на слово 'корпоративный' не нужны, используются все данные по таблице.
    """,
    "fields": {
        # Временные метрики
        "MONTH_DT": {
            "type": "DATE",
            "description": (
                "Отчётная дата. Для закрытых месяцев — последний день месяца "
                "(например, 2026-03-31). Для текущего незакрытого месяца — "
                "последняя доступная дата выгрузки (может НЕ совпадать с концом месяца)."
            ),
            "description_en": (
                "Reporting date. For closed months — last day of the month "
                "(e.g. 2026-03-31). For the current (not yet closed) month — "
                "last available pipeline snapshot date (may NOT be end-of-month)."
            ),
            "category": "Временные метрики",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
            "is_key": True,
        },
        "CREATE_DT": {
            "type": "DATE",
            "description": "Дата открытия первого счета клиента, Дата открытия клиента",
            "description_en": "Date of opening the first account for the client, date of client opening",
            "category": "Временные метрики",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "CLOSE_DT": {
            "type": "DATE",
            "description": "Дата закрытия последнего счета клиента, дата закрытия клиента",
            "description_en": "Date of closure the last account for the client, date of client closure",
            "category": "Временные метрики",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        # Идентификация клиента
        "CUSTOMER_ID": {
            "type": "NUMBER",
            "description": "Код клиента в системе с CFT",
            "description_en": "Client code in CFT system",
            "category": "Идентификация клиента",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "INN": {
            "type": "NUMBER",
            "description": "ИНН клиента",
            "description_en": "Client INN, TIN (Tax Identification Number)",
            "category": "Идентификация клиента",
            "is_key": True,
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "SEG": {
            "type": "VARCHAR2(200)",
            "description": "Сегмент клиента. Значения: International, Middle, SME, FI, Region, Large",
            "description_en": "Client segment. Values: International, Middle, SME, FI, Region, Large",
            "category": "Идентификация клиента",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "GROUP_NM": {
            "type": "VARCHAR2(100)",
            "description": "Наименование группы клиента (группа связанных компаний)",
            "description_en": "Client group name (group of related companies)",
            "category": "Идентификация клиента",
            "is_key": True,
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "ORGANIZATION_NM": {
            "type": "VARCHAR2(500)",
            "description": "Наименование юридического лица - клиента банка",
            "description_en": "Legal entity name - bank client",
            "category": "Идентификация клиента",
            "is_key": True,
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        # Обслуживание
        "DESK": {
            "type": "VARCHAR2(100)",
            "description": "Подразделение (дэск, деск) обслуживающее клиента. Значения: Region 1, International 1, International 2, Middle 1, FI, Large 1.",
            "description_en": "Department (desk) serving the client. Values: Region 1, International 1, International 2, Middle 1, FI, Large 1.",
            "category": "Обслуживание",
            "is_key": True,
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "HUB": {
            "type": "VARCHAR2(100)",
            "description": "Хаб (регион) обслуживания клиента. Значения: HUB VOLGA, HUB URAL, HUB SIBERIA, HUB SOUTH, Москва, HUB NORTH-WEST",
            "description_en": "Hub (Region) serving the client. Values: HUB VOLGA, HUB URAL, HUB SIBERIA, HUB SOUTH, Москва, HUB NORTH-WEST",
            "category": "Обслуживание",
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        "MANAGER_NAME": {
            "type": "VARCHAR2(100)",
            "description": "Фамилия, Имя, Отчество клиентского менеджера, обслуживающего клиента",
            "description_en": "Full name (Last name, First name, Middle name) of the client manager serving the client",
            "category": "Обслуживание",
            "is_key": True,
            "aggregation_between_clients": "N/A",
            "aggregation_between_month": "N/A",
            "weight_field": None,
        },
        # Балансы
        "CA_LCY_SUM": {
            "type": "NUMBER(18,2)",
            "description": "Сумма среднемесячных (среднедневных) остатков на расчетных счетах клиента во всех валютах в рублевом эквиваленте за отчетный месяц. Часть пассивов банка.⚠️ ИТОГОВОЕ ПОЛЕ: включает CA_LCY_RUB_SUM + остатки в по счетам в валюте (поле отсутствует в таблице). Не суммировать с этими полями! Сумма остатков на валютных счетах клиента может быть рассчитана как разница CA_LCY_SUM и CA_LCY_RUB_SUM. Запрещено использовать как сумму остатков на дату, т.к. это среднее за период",
            "description_en": "Total (monthly average, daily average) balance on client's current accounts in all currencies in ruble equivalent. ⚠️ TOTAL FIELD: equals CA_LCY_RUB_SUM + balances on foreign currencies accounts (not in this table). Do not sum with these fields! The balance on foreign currencies accounts is the difference between CA_LCY_SUM and CA_LCY_RUB_SUM. Forbiden to use this field as balance amount on date, as it's an average amount for the period.",
            "category": "Балансы",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "AVG",
            "weight_field": None,
        },
        "CA_LCY_RUB_SUM": {
            "type": "NUMBER(18,2)",
            "description": "Сумма среднемесячных (среднедневных) остатков на рублевых расчетных счетах клиента в рублях за отчетный месяц. Часть пассивов банка. Является частью CA_LCY_SUM. Запрещено использовать как сумму остатков на дату, т.к. это среднее за период",
            "description_en": "Total (monthly average, daily average) balance on client's ruble current accounts in rubles for reporting month. Part of CA_LCY_SUM. Forbiden to use this field as balance amount on date, as it's an average amount for the period.",
            "category": "Балансы",
            "operation_currency": "RUB",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "AVG",
            "weight_field": None,
        },
        # Депозиты
        "DEP_SUM": {
            "type": "NUMBER(18,2)",
            "description": "Сумма среднемесячных (среднедневных) остатков на депозитных счетах (сумма размещенных депозитов) клиента во всех валютах в рублевом эквиваленте за отчетный месяц. Часть пассивов банка. Запрещено использовать как сумму депозитов на дату, т.к. это среднее за период",
            "description_en": "Total (monthly average, daily average) balance on client's deposit accounts in all currencies in ruble equivalent for reporting month. Forbiden to use this field as deposit amount on date, as it's an average amount for the period.",
            "category": "Депозиты",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "AVG",
            "weight_field": None,
        },
        # FX операции
        "FX_VOLUME_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Объем FX (конверсионных) операций по всем валютам в рублевом эквиваленте за отчетный месяц. ИТОГОВОЕ ПОЛЕ: равно FX_EUR_VOLUME_RUB+FX_CNY_VOLUME_RUB+сумма объема по другим валютам(этого поля нет в таблице). Не суммировать с этими полями! Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Volume of FX (conversion) operations in all currencies in ruble equivalent for reporting month. TOTAL FIELD: equals FX_EUR_VOLUME_RUB+FX_CNY_VOLUME_RUB+volume sum for other currencies (this field is not in the table). Do not sum with these fields! Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_CNT": {
            "type": "NUMBER(10)",
            "description": "Количество FX (конверсионных) операций по всем валютам за отчетный месяц. ИТОГОВОЕ ПОЛЕ: равно FX_EUR_CNT+FX_CNY_CNT+сумма количества по другим валютам(этого поля нет в таблице). Не суммировать с этими полями! Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Number of FX (conversion) operations per day in all currencies for reporting month. TOTAL FIELD: equals FX_EUR_CNT+FX_CNY_CNT+count sum for other currencies (this field is not in the table). Do not sum with these fields! Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "N/A",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_EUR_MARGIN_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Сумма маржи (дохода) по FX (конверсионным) операциям клиента по конверсионным по покупке-продаже евро за отчетный месяц в рублях. Является частью FX_MARGIN_RUB, PNL_SUM. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Margin (income) amount from FX (conversion) operations for the client for EUR buy/sell conversions for reporting month in rubles. Part of FX_MARGIN_RUB, PNL_SUM. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "Доходы (PL)",
            "operation_currency": "EUR",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_EUR_VOLUME_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Объем FX (конверсионных) операций по покупке-продаже евро в рублевом эквиваленте за отчетный месяц. Является частью FX_VOLUME_RUB. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Volume of FX (conversion) operations for EUR buy/sell in ruble equivalent for reporting month. Part of FX_VOLUME_RUB. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "EUR",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_EUR_CNT": {
            "type": "NUMBER(10)",
            "description": "Количество FX (конверсионных) операций по покупке-продаже евро за отчетный месяц. Является частью FX_CNT. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Number of FX (conversion) operations for EUR buy/sell for reporting month. Part of FX_CNT. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "EUR",
            "result_currency_equivalent": "N/A",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_CNY_MARGIN_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Сумма маржи (дохода) по FX (конверсионным) операциям клиента по конверсионным по покупке-продаже китайских юаней за отчетный месяц в рублях. Является частью FX_MARGIN_RUB, PNL_SUM. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Margin (income) amount from FX (conversion) operations for the client per day for CNY buy/sell conversions for reporting month in rubles. Part of FX_MARGIN_RUB, PNL_SUM. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "Доходы (PL)",
            "operation_currency": "CNY",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_CNY_VOLUME_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Объем FX (конверсионных) операций по покупке-продаже китайских юаней в рублевом эквиваленте за отчетный месяц. Является частью FX_VOLUME_RUB. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Volume of FX (conversion) operations for CNY buy/sell in ruble equivalent for reporting month. Part of FX_VOLUME_RUB. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "CNY",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_CNY_CNT": {
            "type": "NUMBER(10)",
            "description": "Количество FX (конверсионных) операций по покупке-продаже китайских юаней за отчетный месяц. Является частью FX_CNT. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Number of FX (conversion) operations for CNY buy/sell for reporting month. Part of FX_CNT. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "FX операции",
            "operation_currency": "CNY",
            "result_currency_equivalent": "N/A",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        # Доходы (PL)
        "PNL_SUM": {
            "type": "NUMBER(18,2)",
            "description": "Общая сумма дохода по клиенту за отчетный месяц в рублях. ИТОГОВОЕ ПОЛЕ: равно PL_CA + PL_DEP + PL_VK + PL_VK_OUT + VED_SUM + FX_MARGIN_RUB + прочий доход, сумма которого отсутствует в таблице и может быть вычислена путем вычитания из PNL_SUM суммы перечисленных составляющих полей. Не суммировать с этими полями!",
            "description_en": "Total income for the client for reporting month in rubles. TOTAL FIELD: equals PL_CA + PL_DEP + PL_VK + PL_VK_OUT + VED_SUM + FX_MARGIN_RUB + other income that is not present in the table, amount of other income can be calculated as difference between PNL_SUM and sum of listed detailed fields. Do not sum with these fields!",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "PL_CA": {
            "type": "NUMBER(18,2)",
            "description": "Сумма дохода (процентная маржа) за отчетный месяц по остаткам на расчетных счетах в рублях. Является частью PNL_SUM.",
            "description_en": "Income amount (interest margin) for reporting month from balances on current accounts in rubles. Part of PNL_SUM.",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "PL_DEP": {
            "type": "NUMBER(18,2)",
            "description": "Сумма дохода (процентная маржа) за отчетный месяц по остаткам на депозитах в рублях. Является частью PNL_SUM.",
            "description_en": "Income amount (interest margin) for reporting month from deposit balances in rubles. Part of PNL_SUM.",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "FX_MARGIN_RUB": {
            "type": "NUMBER(18,2)",
            "description": "Сумма маржи (дохода) по FX (конверсионным) операциям клиента за отчетный месяц по всем валютам в рублях. ИТОГОВОЕ ПОЛЕ: равно FX_EUR_MARGIN_RUB+FX_CNY_MARGIN_RUB+сумма маржи по другим валютам(этого поля нет в таблице). Не суммировать с этими полями! Является частью PNL_SUM. Запрещено использовать для валютных платежей (это конверсии/обмен валюты, для валютных платежей используй VED_VOL)",
            "description_en": "Margin (income) amount from FX (conversion) operations for the client for reporting month in all currencies in rubles. TOTAL FIELD: equals FX_EUR_MARGIN_RUB+FX_CNY_MARGIN_RUB+margin sum for other currencies (this field is not in the table). Do not sum with these fields! Part of PNL_SUM. Do not use for foreign currency payments (this is currency conversion/exchange; for foreign currency payments use VED_VOL)",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "PL_VK": {
            "type": "NUMBER(18,2)",
            "description": "Сумма комиссионного дохода по операциям валютного контроля (ВК) за отчетный месяц в рублях по валютным контрактам стоящим на учете в нашем банке. Является частью PNL_SUM. Если в вопросе не детализировано какой доход по валютному контролю нужен, используй оба поля PL_VK (контракт на учете в нашем банке) и PL_VK_OUT (контракт на учете в другом банке)",
            "description_en": "Commission income amount from foreign exchange control operations (VK) for reporting month in rubles for contracts registered in our banks. Part of PNL_SUM. If the question does not specify which income for currency control is required, use both fields: PL_VK (contract registered with our bank) and PL_VK_OUT (contract registered with another bank).",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "PL_VK_OUT": {
            "type": "NUMBER(18,2)",
            "description": "Сумма комиссионного дохода по операциям валютного контроля (ВК) по валютным контрактам стоящим на учете в других банках за отчетный месяц в рублях. Является частью PNL_SUM. Если в вопросе не детализировано какой доход по валютному контролю нужен, используй оба поля PL_VK (контракт на учете в нашем банке) и PL_VK_OUT (контракт на учете в другом банке)",
            "description_en": "Commission income amount from foreign exchange control operations (VK) for reporting month contracts registered in other banks per day (reporting date) in rubles. Part of PNL_SUM. If the question does not specify which income for currency control is required, use both fields: PL_VK (contract registered with our bank) and PL_VK_OUT (contract registered with another bank).",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        "VED_SUM": {
            "type": "NUMBER(18,2)",
            "description": "Сумма комиссионного дохода по ВЭД операциям: валютные трансграничные платежи (валютный ВЭД) и рублевые трансграничные платежи (рублевый ВЭД) за отчетный месяц в рублях. Является частью PNL_SUM.",
            "description_en": "Commission income amount from VED operations: payments in currency abroad, payments in rubles abroad for reporting month in rubles. Part of PNL_SUM.",
            "category": "Доходы (PL)",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        # ВЭД операции
        "VED_VOL": {
            "type": "NUMBER(18,2)",
            "description": "Сумма (объем) ВЭД операций клиента за отчетный месяц в рублевом эквиваленте: валютные трансграничные платежи (валютный ВЭД) и рублевые трансграничные платежи (рублевый ВЭД). Показатель включает общую сумму как входящих так и исходящих ВЭД платежей. ИТОГОВОЕ ПОЛЕ: включает и валютные, и рублевые трансграничные платежи — разделить их нельзя. Используй это поле для вопросов о валютных платежах, трансграничных платежах и ВЭД операциях.",
            "description_en": "Amount (volume) of VED operations: payments in currency abroad, payments in rubles abroad for reporting month in ruble equivalent. Includes sum of incoming and outgoing VED payments. TOTAL FIELD: includes both foreign currency and ruble cross-border payments — cannot be split. Use this field for questions about foreign currency payments, cross-border payments and VED operations.",
            "category": "ВЭД операции",
            "operation_currency": "MULTI",
            "result_currency_equivalent": "RUB",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "SUM",
            "weight_field": None,
        },
        # Активность клиента
        "ACT_1M": {
            "type": "NUMBER(10)",
            "description": "Признак активности клиента в отчетный месяц. Значения: 1 - клиент активный, 0 - клиент спящий",
            "description_en": "A sign of client activity for reporting month. Values: 1 - client active, 0 - client dormant",
            "category": "Активность клиента",
            "operation_currency": "N/A",
            "result_currency_equivalent": "N/A",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "MAX",
            "weight_field": None,
        },
        "ACT_3M": {
            "type": "NUMBER(10)",
            "description": "Признак активности клиента за прошедшие 3 месяца (текущий и два предыдущих). Значения: 1 - клиент активный, 0 - клиент спящий",
            "description_en": "A sigh of client activity for 3 month (current month and previous 2 months). Values: 1 - client active, 0 - client dormant",
            "category": "Активность клиента",
            "operation_currency": "N/A",
            "result_currency_equivalent": "N/A",
            "aggregation_between_clients": "SUM",
            "aggregation_between_month": "MAX",
            "weight_field": None,
        },
    },
    "sql_examples": [
        {
            "question": "какой общий доход за 2025 год?",
            "sql": "SELECT SUM(PNL_SUM) as total_income FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'",
        },
        {
            "question": "сколько уникальных клиентов в базе?",
            "sql": "SELECT COUNT(DISTINCT CUSTOMER_ID) as total_customers FROM client_product",
        },
        {
            "question": "топ-10 клиентов по доходу за 2025 год",
            "sql": "SELECT ORGANIZATION_NM, SUM(PNL_SUM) as total_income FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' GROUP BY ORGANIZATION_NM ORDER BY total_income DESC FETCH FIRST 10 ROWS ONLY",
        },
        {
            "question": "объём FX операций в евро за январь 2025",
            "sql": "SELECT SUM(FX_EUR_VOLUME_RUB) as total_volume FROM client_product WHERE MONTH_DT = DATE '2025-01-31'",
        },
        {
            "question": "остатки на депозитах на последний доступный месяц",
            "sql": "SELECT SUM(DEP_SUM) as total_deposits FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product)",
        },
        {
            "question": "сравни доходы 2024 и 2025 года",
            "sql": "SELECT SUM(CASE WHEN MONTH_DT BETWEEN DATE '2024-01-01' AND DATE '2024-12-31' THEN PNL_SUM ELSE 0 END) as income_2024, SUM(CASE WHEN MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' THEN PNL_SUM ELSE 0 END) as income_2025 FROM client_product WHERE MONTH_DT BETWEEN DATE '2024-01-01' AND DATE '2025-12-31'",
        },
        {
            "question": "у каких групп клиентов вырос доход с 2024 на 2025 год?",
            "sql": """SELECT GROUP_NM,
    SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2024 THEN PNL_SUM ELSE 0 END) as income_2024,
    SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2025 THEN PNL_SUM ELSE 0 END) as income_2025,
    SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2025 THEN PNL_SUM ELSE 0 END) -
    SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2024 THEN PNL_SUM ELSE 0 END) as growth
FROM client_product
WHERE EXTRACT(YEAR FROM MONTH_DT) IN (2024, 2025)
GROUP BY GROUP_NM
HAVING SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2025 THEN PNL_SUM ELSE 0 END) >
       SUM(CASE WHEN EXTRACT(YEAR FROM MONTH_DT) = 2024 THEN PNL_SUM ELSE 0 END);""",
        },
        {
            "question": "остатки на счетах по сегментам клиентов",
            "sql": "SELECT SEG, SUM(CA_LCY_SUM) AS total_balance FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product) GROUP BY SEG ORDER BY total_balance DESC",
        },
        {
            "question": "топ-10 клиентов по доходу за ноябрь 2025",
            "sql": "SELECT ORGANIZATION_NM, CUSTOMER_ID, SUM(PNL_SUM) as total_income FROM client_product WHERE MONTH_DT = DATE '2025-11-30' GROUP BY ORGANIZATION_NM, CUSTOMER_ID ORDER BY total_income DESC FETCH FIRST 10 ROWS ONLY",
        },
        {
            "question": "сколько клиентов обслуживает каждый дэск?",
            "sql": "SELECT DESK, COUNT(DISTINCT CUSTOMER_ID) as clients_count FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product) GROUP BY DESK ORDER BY clients_count DESC",
        },
        {
            "question": "доход от валютного контроля за последний месяц",
            "sql": "SELECT SUM(PL_VK) as vk_income_our_bank, SUM(PL_VK_OUT) as vk_income_other_banks, SUM(PL_VK) + SUM(PL_VK_OUT) as total_vk_income FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product)",
        },
        {
            "question": "клиенты по сегментам",
            "sql": "SELECT SEG, COUNT(DISTINCT CUSTOMER_ID) as customers_count FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product) GROUP BY SEG ORDER BY customers_count DESC",
        },
        {
            "question": "маржа по FX операциям с юанем за сентябрь 2025",
            "sql": "SELECT SUM(FX_CNY_MARGIN_RUB) AS total_fx_cny_margin FROM client_product WHERE MONTH_DT = DATE '2025-09-30'",
        },
        {
            "question": "сколько новых клиентов открыто в 2025 году?",
            "sql": "SELECT COUNT(DISTINCT CUSTOMER_ID) as new_customers FROM client_product WHERE CREATE_DT >= DATE '2025-01-01' AND CREATE_DT <= DATE '2025-12-31'",
        },
        {
            "question": "количество FX операций за 3 квартал 2025",
            "sql": "SELECT SUM(FX_CNT) as total_fx_operations FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-07-01' AND DATE '2025-09-30'",
        },
        {
            "question": "общий доход компании Лукойл за 2025 год",
            "sql": "SELECT ORGANIZATION_NM, SUM(PNL_SUM) AS total_income FROM client_product WHERE UPPER(ORGANIZATION_NM) LIKE '%' || UPPER('Лукойл') || '%' AND MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' GROUP BY ORGANIZATION_NM ORDER BY total_income DESC",
        },
        {
            "question": "доход по хабам за 2025 год",
            "sql": "SELECT HUB, SUM(PNL_SUM) as total_income FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' GROUP BY HUB ORDER BY total_income DESC",
        },
        {
            "question": "сколько активных клиентов за последний месяц?",
            "sql": "SELECT SUM(ACT_1M) as active_clients FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product)",
        },
        {
            "question": "доход по месяцам за 2025 год",
            "sql": "SELECT MONTH_DT, SUM(PNL_SUM) as monthly_income FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' GROUP BY MONTH_DT ORDER BY MONTH_DT",
        },
        {
            "question": "доход от ВК по контрактам в других банках за 2025",
            "sql": "SELECT SUM(PL_VK_OUT) as total_vk_out_income FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'",
        },
        {
            "question": "топ-5 менеджеров по количеству клиентов",
            "sql": "SELECT MANAGER_NAME, COUNT(DISTINCT CUSTOMER_ID) as clients_count FROM client_product WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product) GROUP BY MANAGER_NAME ORDER BY clients_count DESC FETCH FIRST 5 ROWS ONLY",
        },
        {
            "question": "сколько клиентов закрылось в 2025 году?",
            "sql": "SELECT COUNT(DISTINCT CUSTOMER_ID) as closed_clients FROM client_product WHERE CLOSE_DT >= DATE '2025-01-01' AND CLOSE_DT <= DATE '2025-12-31'",
        },
        {
            "question": "объём ВЭД операций за 2025 год",
            "sql": "SELECT SUM(VED_VOL) as total_ved_volume FROM client_product WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'",
        },
        {
            "question": "средние остатки на расчетных счетах по месяцам в 2025 году (всего и по рублевым)",
            "sql": """SELECT
    MONTH_DT,
    SUM(CA_LCY_SUM) AS total_balance_all_currencies,
    SUM(CA_LCY_RUB_SUM) AS balance_rub
FROM client_product
WHERE MONTH_DT BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
GROUP BY MONTH_DT
ORDER BY MONTH_DT""",
        },
    ],
}


def get_table_metadata(table_name: str = "client_product") -> dict[str, Any]:
    """Возвращает метаданные указанной таблицы."""
    if table_name == "client_product":
        return ALL_CLI_METADATA
    raise ValueError(f"Таблица {table_name} не найдена в метаданных")


def get_sql_examples(table_name: str = "client_product") -> list[dict[str, str]]:
    """Возвращает примеры SQL запросов для таблицы."""
    metadata = get_table_metadata(table_name)
    examples: list[dict[str, str]] = metadata.get("sql_examples", [])
    return examples
