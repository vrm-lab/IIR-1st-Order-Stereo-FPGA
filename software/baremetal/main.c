#include <stdio.h>
#include <stdint.h>   // <-- PENTING: Untuk int16_t
#include <string.h>   // <-- PENTING: Untuk memset
#include "xil_types.h" // <-- PENTING: Untuk u8, u32
#include "xil_io.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_printf.h"
#include "xil_cache.h"

// =========================================================
// 1. HARDWARE ADDRESS DEFINITIONS
// =========================================================
// NOTE: Base addresses must match Vivado Address Editor
// Update these values according to your system.xsa
#define IIR_BASE_ADDR       0xA0010000  // Alamat IP Stereo Filter
#define DMA_BASE_ADDR       0xA0000000  // Alamat AXI DMA, Status: Reserved
#define DMA_DEV_ID          0

// Offset Register Filter IIR
#define REG_CTRL_OFFSET     0x00
#define REG_A0_OFFSET       0x04
#define REG_A1_OFFSET       0x08
#define REG_B1_OFFSET       0x0C

// Konfigurasi Buffer DMA
#define MEM_BASE_ADDR       0x10000000  // RAM lokasi data (DDR)
#define RX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00100000) // Offset 1MB
#define TX_BUFFER_BASE      (MEM_BASE_ADDR + 0x00200000) // Offset 2MB
#define TEST_LENGTH         128         // Jumlah sampel test

XAxiDma AxiDma;

// =========================================================
// 2. DRIVER FUNGSI FILTER
// =========================================================
void IIR_Set_Coefficients(float a0, float a1, float b1) {
    // Konversi Float ke Fixed Point Q1.15
    int16_t a0_fixed = (int16_t)(a0 * 32768.0f);
    int16_t a1_fixed = (int16_t)(a1 * 32768.0f);
    int16_t b1_fixed = (int16_t)(b1 * 32768.0f);

    Xil_Out32(IIR_BASE_ADDR + REG_A0_OFFSET, a0_fixed);
    Xil_Out32(IIR_BASE_ADDR + REG_A1_OFFSET, a1_fixed);
    Xil_Out32(IIR_BASE_ADDR + REG_B1_OFFSET, b1_fixed);
    
    xil_printf("Coeffs Updated: A0=%d, A1=%d, B1=%d\r\n", a0_fixed, a1_fixed, b1_fixed);
}

void IIR_Enable(u8 enable, u8 clear) {
    u32 val = 0;
    if (enable) val |= 0x01;
    if (clear)  val |= 0x02;
    Xil_Out32(IIR_BASE_ADDR + REG_CTRL_OFFSET, val);
}

// =========================================================
// 3. MAIN PROGRAM
// =========================================================
int main()
{
    // Enable Cache Manual
    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("\r\n--- Stereo IIR Filter Test on Kria KV260 ---\r\n");

    // --- A. Init DMA ---
    XAxiDma_Config *CfgPtr;
    CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!CfgPtr) {
        xil_printf("DMA Config not found\r\n");
        return XST_FAILURE;
    }
    
    int Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
    if (Status != XST_SUCCESS) {
        xil_printf("DMA Init Failed\r\n");
        return XST_FAILURE;
    }
    
    // Disable Interrupts (Polling Mode)
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    // --- B. Siapkan Data Test (Impulse Signal) ---
    u32 *TxBufferPtr = (u32 *)TX_BUFFER_BASE;
    u32 *RxBufferPtr = (u32 *)RX_BUFFER_BASE;

    // Bersihkan RX Buffer
    memset((void *)RX_BUFFER_BASE, 0, TEST_LENGTH * 4);

    // Isi TX Buffer dengan Impulse: [L=10000, R=10000] di index 0
    TxBufferPtr[0] = (10000 << 16) | (10000 & 0xFFFF); 
    
    for(int i = 1; i < TEST_LENGTH; i++) {
        TxBufferPtr[i] = 0x00000000; // Sisa nol
    }

    // Flush Cache (Penting agar DMA membaca data terbaru dari RAM)
    Xil_DCacheFlushRange((UINTPTR)TxBufferPtr, TEST_LENGTH * 4);
    Xil_DCacheFlushRange((UINTPTR)RxBufferPtr, TEST_LENGTH * 4);

    // --- C. Setup Filter (LPF Decay) ---
    IIR_Enable(1, 1); // Enable + Clear
    IIR_Set_Coefficients(0.5f, 0.0f, 0.5f);
    IIR_Enable(1, 0); // Enable + Run

    xil_printf("Filter Configured via AXI-Lite.\r\n");

    // --- D. Transfer DMA ---
    // 1. RX (Terima) - Pastikan S2MM jalan duluan
    Status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBufferPtr,
                TEST_LENGTH * 4, XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        xil_printf("DMA RX Failed\r\n");
        return XST_FAILURE;
    }

    // 2. TX (Kirim)
    Status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)TxBufferPtr,
                TEST_LENGTH * 4, XAXIDMA_DMA_TO_DEVICE);
    if (Status != XST_SUCCESS) {
        xil_printf("DMA TX Failed\r\n");
        return XST_FAILURE;
    }

    // 3. Polling Wait
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE) ||
           XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA)) {
           // Tunggu sampai DMA kelar...
    }

    // Invalidate Cache (Agar CPU membaca data terbaru hasil DMA)
    Xil_DCacheInvalidateRange((UINTPTR)RxBufferPtr, TEST_LENGTH * 4);

    // --- E. Cek Hasil ---
    xil_printf("\r\n--- DMA Transfer Done. Checking Result ---\r\n");
    for(int i = 0; i < 10; i++) { 
        int16_t left_out  = (int16_t)(RxBufferPtr[i] >> 16);
        int16_t right_out = (int16_t)(RxBufferPtr[i] & 0xFFFF);
        xil_printf("Sample[%d]: L=%d, R=%d\r\n", i, left_out, right_out);
    }

    return 0;
}