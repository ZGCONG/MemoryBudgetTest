import SwiftUI
import Charts
import os

struct ContentView: View {
    private let crashMemoryFileName = "CrashMemory.dat"
    private let memoryWarningsFileName = "MemoryWarnings.dat"
    
    @State private var allocatedMB: Int = 0
    @State private var physicalMemorySizeMB: Int = 1
    @State private var userMemorySizeMB: Int = 0
    @State private var isRunning = false
    
    @State private var savedCrashMemory: Int? = nil
    @State private var savedWarningMemory: Int? = nil
    
    @State private var historyMarkers: [MemoryMarker] = []
    
    @State private var timer: Timer?
    @State private var allocatedPointers: [UnsafeMutableRawPointer] = []
    @State private var firstMemoryWarningReceived = false
    
    private let memoryWarningPublisher = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("内存分配实时状态图表")) {
                    Chart {
                        BarMark(
                            x: .value("类别", "当前 App 占用"),
                            y: .value("内存 (MB)", allocatedMB)
                        )
                        .foregroundStyle(.blue.gradient)
                        
                        RuleMark(y: .value("可用上限", userMemorySizeMB))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundStyle(.purple)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("可用上限: \(userMemorySizeMB)MB")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                    .bold()
                            }
                        
                        ForEach(historyMarkers) { marker in
                            RuleMark(y: .value(marker.label, marker.memory))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: marker.type == .crash ? [] : [3]))
                                .foregroundStyle(marker.type == .crash ? Color.red : Color.orange)
                                .annotation(
                                    position: marker.type == .crash ? .top : .bottom,
                                    alignment: marker.type == .crash ? .leading : .trailing
                                ) {
                                    Text("\(marker.label): \(marker.memory)MB")
                                        .font(.caption2)
                                        .foregroundColor(marker.type == .crash ? .red : .orange)
                                        .bold()
                                        .padding(.horizontal, 4)
                                        .background(Color(.systemBackground).opacity(0.7))
                                        .cornerRadius(4)
                                }
                        }
                    }
                    .chartYScale(domain: 0...physicalMemorySizeMB)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)MB")
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("数据指标面板")) {
                    HStack {
                        Text("应用识别内存总量")
                        Spacer()
                        Text("\(physicalMemorySizeMB)MB")
                            .bold()
                    }

                    HStack {
                        Text("应用最大可用上限")
                        Spacer()
                        Text("\(userMemorySizeMB)MB")
                            .bold()
                            .foregroundColor(.purple)
                    }
                    
                    LabeledContent {
                        if isRunning {
                            if let currentWarning = historyMarkers.first(where: { $0.label == "本次内存警告" }) {
                                Text("\(currentWarning.memory)MB")
                                    .bold()
                                    .foregroundColor(.orange)
                            } else {
                                Text("等待警告中...")
                                    .foregroundColor(.secondary)
                            }
                        } else if let warning = savedWarningMemory {
                            Text("\(warning)MB")
                                .bold()
                                .foregroundColor(.orange)
                        } else {
                            Text("暂无数据").foregroundColor(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.orange)
                            Text("内存调用警告线")
                        }
                    }
                    
                    LabeledContent {
                        if isRunning {
                            Text("计算中...")
                                .foregroundColor(.secondary)
                        } else if let crash = savedCrashMemory {
                            Text("\(crash)MB")
                                .bold()
                                .foregroundColor(.red)
                        } else {
                            Text("暂无数据").foregroundColor(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("内存调用崩溃线")
                        }
                    }
                }
                
                Section(
                    header: Text("测试操作"),
                    footer: Text("这是一个小型的内存分配测试程序，试图让系统分配尽可能多的内存以达到崩溃，并记录内存警告和发生崩溃的内存值，当您再次运行应用程序，即可查看软件崩溃需要多少内存以及何时发生内存警告，这有助于了解设备的内存分配预算。")
                        .lineSpacing(4)
                ) {
                    Button(action: startTesting) {
                        HStack {
                            Spacer()
                            if isRunning {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("当前已分配 \(allocatedMB)MB")
                            } else {
                                Image(systemName: "play.fill")
                                Text("开始分配测试 (Start)")
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(isRunning ? Color.gray : Color.green)
                    .disabled(isRunning)
                }
            }
            .navigationTitle("Memory Budget")
            .onAppear {
                refreshMemoryInfo()
                loadHistoryData()
            }
            .onReceive(memoryWarningPublisher) { _ in
                handleMemoryWarning()
            }
        }
    }
    
    private func startTesting() {
        clearAll()
        firstMemoryWarningReceived = false
        isRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            allocateMemory()
        }
    }
    
    private func allocateMemory() {
        let sizeInBytes = 1048576
        
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: sizeInBytes, alignment: MemoryLayout<UInt8>.alignment)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: sizeInBytes)
        
        allocatedPointers.append(pointer)
        allocatedMB += 1
        
        refreshMemoryInfo()
        
        if firstMemoryWarningReceived {
            if let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let crashFileUrl = documentDirectory.appendingPathComponent(crashMemoryFileName)
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSNumber(value: allocatedMB), requiringSecureCoding: false) {
                    try? data.write(to: crashFileUrl)
                }
            }
        }
    }
    
    private func handleMemoryWarning() {
        firstMemoryWarningReceived = true
        
        let newWarning = MemoryMarker(label: "本次内存警告", memory: allocatedMB, type: .warning)
        historyMarkers.append(newWarning)
        
        let currentWarnings = [allocatedMB]
        if let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let warningsFileUrl = documentDirectory.appendingPathComponent(memoryWarningsFileName)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: currentWarnings, requiringSecureCoding: false) {
                try? data.write(to: warningsFileUrl)
            }
        }
    }
    
    private func clearAll() {
        timer?.invalidate()
        timer = nil
        
        for pointer in allocatedPointers {
            pointer.deallocate()
        }
        allocatedPointers.removeAll()
        allocatedMB = 0
        
        historyMarkers.removeAll()
        isRunning = false
    }
    
    private func refreshMemoryInfo() {
        var physicalMemorySize: UInt64 = 0
        var sysInfoName: [Int32] = [CTL_HW, HW_MEMSIZE]
        var size = MemoryLayout<UInt64>.size
        sysctl(&sysInfoName, 2, &physicalMemorySize, &size, nil, 0)
        physicalMemorySizeMB = Int(physicalMemorySize / 1048576)
        
        if #available(iOS 15.0, *) {
            let availableInBytes = os_proc_available_memory()
            userMemorySizeMB = Int(availableInBytes / 1048576) + allocatedMB
        } else {
            var userMemorySize: UInt64 = 0
            sysInfoName[1] = HW_USERMEM
            sysctl(&sysInfoName, 2, &userMemorySize, &size, nil, 0)
            userMemorySizeMB = Int(userMemorySize / 1048576)
        }
    }
    
    private func loadHistoryData() {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let crashFileUrl = documentDirectory.appendingPathComponent(crashMemoryFileName)
        let warningsFileUrl = documentDirectory.appendingPathComponent(memoryWarningsFileName)
        
        historyMarkers.removeAll()
        savedCrashMemory = nil
        savedWarningMemory = nil
        
        if let data = try? Data(contentsOf: crashFileUrl),
           let crashMemory = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSNumber.self, from: data)?.intValue,
           crashMemory > 0 {
            savedCrashMemory = crashMemory
            historyMarkers.append(MemoryMarker(label: "调用崩溃线", memory: crashMemory, type: .crash))
        }
        
        if let data = try? Data(contentsOf: warningsFileUrl),
           let lastMemoryWarnings = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSNumber.self], from: data) as? [Int],
           let firstWarning = lastMemoryWarnings.first {
            savedWarningMemory = firstWarning
            historyMarkers.append(MemoryMarker(label: "调用警告线", memory: firstWarning, type: .warning))
        }
    }
}

enum MarkerType {
    case crash
    case warning
}

struct MemoryMarker: Identifiable {
    let id = UUID()
    let label: String
    let memory: Int
    let type: MarkerType
}

#Preview {
    ContentView()
}
