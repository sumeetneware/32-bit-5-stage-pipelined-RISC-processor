# 32-bit 5-Stage Pipelined RISC Processor (Verilog)

A complete Verilog CPU project implementing a 32-bit pipelined RISC processor with hazard detection, forwarding, branch flush logic, direct-mapped I/D caches, and performance metrics.

## Features
- 5-stage pipeline: IF, ID, EX, MEM, WB
- Instruction set:
  - R-type: `ADD`, `SUB`, `AND`, `OR`
  - Memory: `LW`, `SW`
  - Branch: `BEQ`
- Hazard mitigation:
  - Load-use stall logic
  - EX/MEM and MEM/WB forwarding
- Branch handling:
  - Branch resolution in EX
  - Pipeline flush on taken branch
- Cache integration:
  - Direct-mapped I-cache (16 lines)
  - Direct-mapped D-cache (16 lines, write-through, write-allocate)
- Performance metrics:
  - Cycle count
  - Retired instruction count
  - CPI
  - I$/D$ hit/miss/access counters and hit rates

## Architecture Diagram

```mermaid
flowchart LR
    IMEM["Instruction Memory"] --> IC["I-Cache"]
    IC --> IFID["IF/ID"]
    IFID --> ID["Decode + Register File + Control"]
    ID --> IDEX["ID/EX"]
    IDEX --> EX["ALU + Forwarding + Branch Check"]
    EX --> EXMEM["EX/MEM"]
    EXMEM --> DC["D-Cache"]
    DC --> DMEM["Data Memory (Backing)"]
    DC --> MEMWB["MEM/WB"]
    MEMWB --> WB["Write Back"]
    WB --> ID
    EX --> IFID
