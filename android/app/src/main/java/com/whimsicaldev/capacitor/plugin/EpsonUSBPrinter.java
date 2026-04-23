package com.whimsicaldev.capacitor.plugin;

import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.util.Log;

import com.csnprintersdk.csnio.CSNUSBPrinting;
import com.csnprintersdk.csnio.CSNPOS;

import org.json.JSONArray;
import org.json.JSONObject;

public class EpsonUSBPrinter {
    private static final String TAG = "EpsonUSBPrinter";
    private static final Charset PRINTER_CHARSET = Charset.forName("GBK");
    private static final int PRINT_WIDTH = 32;
    private final Context context;
    private final String actionString;
    private final UsbManager manager;
    private final Object lock = new Object();
    private UsbDevice connectedDevice;
    CSNPOS mPos = new CSNPOS();
	CSNUSBPrinting mUsb = new CSNUSBPrinting();

    public String echo(String value) {
        Log.i("Echo", value);
        return value;
    }

    public EpsonUSBPrinter(Context context) {
        this.context = context;
        mPos.Set(mUsb);
        this.actionString = this.context.getPackageName() + ".USB_PERMISSION";
        this.manager =  (UsbManager) this.context.getSystemService(Context.USB_SERVICE);
    }

    public String getPermissionAction() {
        return actionString;
    }

    public List<Map<String, Object>> getPrinterList() {
        List<Map<String, Object>> printerList = new ArrayList<>();

        HashMap<String, UsbDevice> deviceList = this.manager.getDeviceList();
        for (UsbDevice usbDevice : deviceList.values()) {
            boolean isPrinter = isAPrinter(usbDevice);
            Map<String, Object> printerInfo = new HashMap<>();
            printerInfo.put("deviceId", usbDevice.getDeviceId());
            printerInfo.put("vendorId", usbDevice.getVendorId());
            printerInfo.put("productId", usbDevice.getProductId());
            printerInfo.put("productName", usbDevice.getProductName());
            printerInfo.put("manufacturerName", usbDevice.getManufacturerName());
            printerInfo.put("hasPermission", manager.hasPermission(usbDevice));
            printerInfo.put("isConnected", isConnectedTo(usbDevice));
            printerInfo.put("isPrinter", isPrinter);
            printerList.add(printerInfo);
        }

        return printerList;
    }

    public String POS_RTQueryStatus(Integer deviceId, Integer vendorId, Integer productId) throws Exception {
        ensureConnected(deviceId, vendorId, productId);

        byte[] status = new byte[1];
        if (this.mPos.POS_RTQueryStatus(status, 2, 3000, 2)) {
            if ((status[0] & 0x12) == 0x12) {
                return "PRINT_NORMAL";
            } else if ((status[0] & 0x76) == 0x76) {
                return "PRINT_COVER_OPEN";
            } else if ((status[0] & 0x72) == 0x72) {
                return "PRINT_OUT_OF_PAPER";
            } else {
                return "UNKNOWN_STATUS";
            }
        }
        throw new Exception("Failed to query printer status.");
    }

    private boolean isAPrinter(UsbDevice usbDevice) {
        for (int i = 0; i < usbDevice.getInterfaceCount(); i += 1) {
            UsbInterface usbInterface = usbDevice.getInterface(i);
            for (int j = 0; j < usbInterface.getEndpointCount(); j++) {
                UsbEndpoint usbEndpoint = usbInterface.getEndpoint(j);
                if (UsbConstants.USB_ENDPOINT_XFER_BULK == usbEndpoint.getType()
                        && UsbConstants.USB_DIR_OUT == usbEndpoint.getDirection()) {
                    return true;
                }
            }
        }
        return false;
    }

    private boolean isConnectedTo(UsbDevice device) {
        return connectedDevice != null
                && connectedDevice.getDeviceId() == device.getDeviceId()
                && mPos.GetIO().IsOpened();
    }

    public void requestPermission(UsbDevice device) {
        if (manager.hasPermission(device)) {
            return;
        }
        PendingIntent mPermissionIntent = PendingIntent.getBroadcast(
                this.context,
                0,
                new Intent(actionString),
                PendingIntent.FLAG_IMMUTABLE
        );
        manager.requestPermission(device, mPermissionIntent);
    }

    public boolean requestPermissionByIds(Integer deviceId, Integer vendorId, Integer productId) {
        UsbDevice device = findDevice(deviceId, vendorId, productId);
        if (device == null) {
            return false;
        }
        requestPermission(device);
        return true;
    }

    private UsbDevice findDevice(Integer deviceId, Integer vendorId, Integer productId) {
        HashMap<String, UsbDevice> deviceList = this.manager.getDeviceList();
        if (deviceId != null) {
            for (UsbDevice device : deviceList.values()) {
                if (deviceId == device.getDeviceId()) {
                    return device;
                }
            }
        }

        if (vendorId != null && productId != null) {
            for (UsbDevice device : deviceList.values()) {
                if (vendorId == device.getVendorId() && productId == device.getProductId()) {
                    return device;
                }
            }
        }

        if (productId != null) {
            for (UsbDevice device : deviceList.values()) {
                if (productId == device.getProductId()) {
                    return device;
                }
            }
        }

        return null;
    }

    private void ensureConnected(Integer deviceId, Integer vendorId, Integer productId) throws Exception {
        UsbDevice selectedDevice = findDevice(deviceId, vendorId, productId);
        if (selectedDevice == null) {
            throw new Exception("USB device not found.");
        }

        synchronized (lock) {
            if (isConnectedTo(selectedDevice)) {
                return;
            }

            if (!manager.hasPermission(selectedDevice)) {
                requestPermission(selectedDevice);
                throw new Exception("USB_PERMISSION_REQUIRED");
            }

            try {
                if (mPos.GetIO().IsOpened()) {
                    mUsb.Close();
                }

                boolean opened = this.mUsb.Open(this.manager, selectedDevice, this.context);
                if (!opened) {
                    throw new Exception("Failed to open USB connection.");
                }
                connectedDevice = selectedDevice;
            } catch (Exception e) {
                connectedDevice = null;
                throw new Exception("Failed to establish connection: " + e.getMessage());
            }
        }
    }

    public boolean connectToPrinter(Integer deviceId, Integer vendorId, Integer productId) throws Exception {
        ensureConnected(deviceId, vendorId, productId);
        return true;
    }

    public void disconnect() {
        synchronized (lock) {
            try {
                if (mPos.GetIO().IsOpened()) {
                    mUsb.Close();
                }
            } catch (Exception e) {
                Log.w(TAG, "Failed to close USB connection", e);
            } finally {
                connectedDevice = null;
            }
        }
    }

    public void POS_Reset() throws Exception {
        this.mPos.POS_Reset();
    }

    public void POS_FeedLine() throws Exception {
        this.mPos.POS_FeedLine();
    }

    public void POS_TextOut(String text, int nLan, int nOrgx, int nWidthTimes, int nHeightTimes, int nFontType, int nFontStyle) throws Exception {
        this.mPos.POS_TextOut(text, nLan, nOrgx, nWidthTimes, nHeightTimes, nFontType, nFontStyle);
    }

    public void POS_HalfCutPaper() throws Exception {
        this.mPos.POS_FeedLine();
        this.mPos.POS_FeedLine();
        this.mPos.POS_HalfCutPaper();
        this.mPos.POS_FeedLine();
        this.mPos.POS_FeedLine();
        try {
            Thread.currentThread();
            Thread.sleep(4000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    public void POS_FullCutPaper() throws Exception {
        this.mPos.POS_FeedLine();
        this.mPos.POS_FeedLine();
        this.mPos.POS_FullCutPaper();
        this.mPos.POS_FeedLine();
        this.mPos.POS_FeedLine();
        try {
            Thread.currentThread();
            Thread.sleep(4000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    public void POS_S_Align(int nAlign) throws Exception {
        this.mPos.POS_S_Align(nAlign);
    }


    public void print(String printObject, int lineFeed, Integer deviceId, Integer vendorId, Integer productId) throws Exception {
        ensureConnected(deviceId, vendorId, productId);
        this.mPos.POS_Reset();

        writeRaw(new byte[]{0x1B, 0x40});
        JSONArray resObj = new JSONArray(printObject);
        int maxNOrgx = maxNOrgx(resObj);
        LineBuffer rowBuffer = new LineBuffer(PRINT_WIDTH);
        for (int i = 0; i < resObj.length(); i++) {
            JSONObject jsonobject = resObj.getJSONObject(i);
            String type = jsonobject.getString("type");

            switch (type) {
                case "text":
                    String text = jsonobject.optString("text", "");
                    JSONObject options = jsonobject.optJSONObject("options");
                    if (options == null) {
                        options = new JSONObject();
                    }
                    int align = options.has("align") ? options.getInt("align") : 0;
                    int nLan = options.has("nLan") ? options.getInt("nLan") : 0;
                    int nOrgx = options.has("nOrgx") ? options.getInt("nOrgx") : 0;
                    int fontType = options.has("fontType") ? options.getInt("fontType") : 0;
                    int fontStyle = options.has("fontStyle") ? options.getInt("fontStyle") : 0;
                    int widthTimes = options.has("widthTimes") ? options.getInt("widthTimes") : 0;
                    int heightTimes = options.has("heightTimes") ? options.getInt("heightTimes") : 0;
                    if (options.optBoolean("bold", false)) {
                        fontStyle = 1;
                    }
                    if ("lg".equalsIgnoreCase(options.optString("size", ""))) {
                        widthTimes = Math.max(widthTimes, 1);
                        heightTimes = Math.max(heightTimes, 1);
                    }
                    if (align == 0 && options.has("nOrgx") && maxNOrgx > 0) {
                        rowBuffer.insert(mapOrgxToChar(nOrgx, maxNOrgx), oneLine(text));
                        break;
                    }
                    flushRowBuffer(rowBuffer);
                    printRawText(text, align, widthTimes, heightTimes, fontStyle);
                    break;
                case "dottedLine":
                    flushRowBuffer(rowBuffer);
                    printRawText("--------------------------------", 0, 0, 0, 0);
                    break;
                case "feedLine":
                    flushRowBuffer(rowBuffer);
                    writeRaw("\r\n".getBytes(PRINTER_CHARSET));
                    break;
                case "halfCutPaper":
                    flushRowBuffer(rowBuffer);
                    writeRaw(new byte[]{0x1B, 0x64, 0x03, 0x1D, 0x56, 0x01});
                    break;
                case "fullCutPaper":
                    flushRowBuffer(rowBuffer);
                    writeRaw(new byte[]{0x1B, 0x64, 0x03, 0x1D, 0x56, 0x00});
                    break;
                default:
                    flushRowBuffer(rowBuffer);
                    break;
            }
        }

        flushRowBuffer(rowBuffer);
        for (int i = 0; i < lineFeed; i++) {
            writeRaw("\r\n".getBytes(PRINTER_CHARSET));
        }
        // List<EpsonUSBPrinterLineEntry> printObjectList = this.objectMapper.readValue(printObject, new TypeReference<>() {});
        // Toast.makeText(this.context, "Print started", Toast.LENGTH_LONG).show();
        // this.mPos.POS_Reset();
        // for(EpsonUSBPrinterLineEntry lineEntry: printObjectList) {
        //     Toast.makeText(this.context,lineEntry.getType(), Toast.LENGTH_LONG).show();
        //     switch (lineEntry.getType()) {
        //         case "text":


        //             // this.mPos.POS_S_Align(align);
        //             // this.mPos.POS_TextOut(lineEntry.getLineText(), 0, 0, widthTimes, heightTimes, bold, 0);
        //             break;
        //         case "dottedLine":
        //             this.mPos.POS_TextOut("------------------------------------------\r\n", 0, 0, 0, 0, 0, 0);
        //             break;
        //         case "feedLine":
        //             this.mPos.POS_FeedLine();
        //             break;
        //         case "halfCutPaper":
        //             this.mPos.POS_HalfCutPaper();
        //             break;
        //         case "fullCutPaper":
        //             this.mPos.POS_FullCutPaper();
        //             break;
        //         default:
        //             break;
        //     }
        // }
       // Toast.makeText(this.context, "Print Ended", Toast.LENGTH_LONG).show();
    }

    private void flushRowBuffer(LineBuffer rowBuffer) throws Exception {
        if (!rowBuffer.hasContent()) {
            return;
        }
        printRawText(rowBuffer.take(), 0, 0, 0, 0);
    }

    private void printRawText(String text, int align, int widthTimes, int heightTimes, int fontStyle) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();

        int safeAlign = align;
        if (safeAlign < 0 || safeAlign > 2) {
            safeAlign = 0;
        }
        out.write(new byte[]{0x1B, 0x61, (byte) safeAlign});

        boolean bold = fontStyle > 0;
        out.write(new byte[]{0x1B, 0x45, (byte) (bold ? 1 : 0)});

        int width = widthTimes > 0 ? 1 : 0;
        int height = heightTimes > 0 ? 1 : 0;
        int size = (width << 4) | height;
        out.write(new byte[]{0x1D, 0x21, (byte) size});

        out.write(ensureLineEnding(text).getBytes(PRINTER_CHARSET));

        out.write(new byte[]{0x1D, 0x21, 0x00});
        out.write(new byte[]{0x1B, 0x45, 0x00});
        out.write(new byte[]{0x1B, 0x61, 0x00});

        writeRaw(out.toByteArray());
    }

    private void writeRaw(byte[] data) throws Exception {
        if (data == null || data.length == 0) {
            return;
        }
        int written = this.mPos.GetIO().Write(data, 0, data.length);
        if (written < 0) {
            throw new Exception("USB write failed");
        }
    }

    private int maxNOrgx(JSONArray printObject) {
        int max = 0;
        for (int i = 0; i < printObject.length(); i++) {
            JSONObject obj = printObject.optJSONObject(i);
            if (obj == null || !"text".equals(obj.optString("type"))) {
                continue;
            }
            JSONObject options = obj.optJSONObject("options");
            if (options == null || !options.has("nOrgx")) {
                continue;
            }
            int value = options.optInt("nOrgx", 0);
            if (value > max) {
                max = value;
            }
        }
        return max;
    }

    private int mapOrgxToChar(int nOrgx, int maxNOrgx) {
        if (maxNOrgx <= 0) {
            return 0;
        }
        int scaled = Math.round((float) nOrgx * (PRINT_WIDTH - 1) / (float) maxNOrgx);
        if (scaled < 0) {
            return 0;
        }
        if (scaled >= PRINT_WIDTH) {
            return PRINT_WIDTH - 1;
        }
        return scaled;
    }

    private String oneLine(String text) {
        if (text == null) {
            return "";
        }
        return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").trim();
    }

    private String ensureLineEnding(String text) {
        if (text == null || text.length() == 0) {
            return "\r\n";
        }

        String normalized = text
                .replace("₹", "Rs ")
                .replace("\r\n", "\n")
                .replace("\r", "\n");
        if (!normalized.endsWith("\n")) {
            normalized = normalized + "\n";
        }
        return normalized.replace("\n", "\r\n");
    }

    private static class LineBuffer {
        private final char[] chars;
        private boolean hasContent = false;

        LineBuffer(int width) {
            chars = new char[width];
            reset();
        }

        boolean hasContent() {
            return hasContent;
        }

        void insert(int position, String text) {
            if (text == null || text.length() == 0) {
                return;
            }
            int pos = Math.max(0, Math.min(position, chars.length - 1));
            int available = chars.length - pos;
            int len = Math.min(text.length(), available);
            for (int i = 0; i < len; i++) {
                chars[pos + i] = text.charAt(i);
            }
            hasContent = true;
        }

        String take() {
            int end = chars.length;
            while (end > 0 && chars[end - 1] == ' ') {
                end--;
            }
            String value = new String(chars, 0, end);
            reset();
            return value;
        }

        private void reset() {
            for (int i = 0; i < chars.length; i++) {
                chars[i] = ' ';
            }
            hasContent = false;
        }
    }
}
