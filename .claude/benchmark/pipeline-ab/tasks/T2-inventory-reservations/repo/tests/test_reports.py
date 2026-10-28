from inventory.reports import StockRow, stock_report


def test_stock_report_lists_every_sku_sorted(service, repo):
    service.receive("TEE", "WH1", 8)
    service.place_order("WH1", {"TEE": 3})
    assert stock_report(repo, service, "WH1") == [
        StockRow("CAP", 0, 0, 0),
        StockRow("MUG", 0, 0, 0),
        StockRow("TEE", 8, 3, 5),
    ]
