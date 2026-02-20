package com.whimsicaldev.capacitor.plugin;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class EpsonUSBPrinterLineEntry {
    private String lineText;
    private String text = null;
    private String type;
    private Map<Integer, Object> options = new HashMap<>();
    private List<String> lineStyleList;
    private List<String> lineCommandList;

    public EpsonUSBPrinterLineEntry() {}

    public String getLineText() {
        return lineText;
    }

    public void setLineText(String lineText) {
        this.lineText = lineText;
    }

    public String getText() {
        return text;
    }

    public void setText(String text) {
        this.text = text;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public Map<Integer, Object> getOptions() {
        return options;
    }

    public void setOptions(Map<Integer, Object> options) {
        this.options = options;
    }

    public List<String> getLineStyleList() {
        return lineStyleList;
    }

    public void setLineStyleList(List<String> lineStyleList) {
        this.lineStyleList = lineStyleList;
    }

    public List<String> getLineCommandList() {
        return lineCommandList;
    }

    public void setLineCommandList(List<String> lineCommandList) {
        this.lineCommandList = lineCommandList;
    }
}
