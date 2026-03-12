import SwiftUI

struct HomeButton: View {
    
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            
            Image(systemName: icon)
                .font(.title2)
            
            Text(title)
                .font(.headline)
            
            Spacer()
            
            Image(systemName: "chevron.right")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
