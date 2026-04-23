import SwiftUI
import PhotosUI

struct UploadReportView: View {
    @EnvironmentObject private var app: AppController
    @State private var hazardType = "Pothole"
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    private let hazardTypes = ["Pothole", "Crack"]

    var body: some View {
        FormScreen(title: "Manual Report", subtitle: "Create a Firestore report with Cloudinary image upload.") {
            Picker("Hazard Type", selection: $hazardType) {
                ForEach(hazardTypes, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo")
                    Text(selectedImage == nil ? "Choose Image" : "Change Image")
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(14)
                .background(Color.appDark900)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onChange(of: selectedItem) { _, item in
                Task { await loadImage(from: item) }
            }

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LocationStatus()

            Button {
                app.locationService.requestPermission()
                app.createManualReport(image: selectedImage, hazardType: hazardType)
            } label: {
                Text(app.isUploadingReport ? "Saving..." : "Submit Report")
                    .primaryButtonStyle()
            }
            .disabled(app.isUploadingReport)

            if let message = app.uploadMessage {
                StatusText(message: message, color: message == "Report saved." ? .appSuccess : .appWarning)
            }
        }
        .onAppear { app.locationService.requestPermission() }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run { selectedImage = UIImage(data: data) }
    }
}

struct LocationStatus: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        let coordinate = app.locationService.currentCoordinate
        let text = coordinate.map { String(format: "GPS %.5f, %.5f", $0.latitude, $0.longitude) } ?? "Waiting for GPS location"
        StatusText(message: text, color: coordinate == nil ? .appWarning : .appSuccess)
    }
}
