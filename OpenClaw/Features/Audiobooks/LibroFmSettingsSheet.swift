//
//  LibroFmSettingsSheet.swift
//  OpenClaw
//
//  Libro.fm account management sheet (login/status/logout)
//

import SwiftUI

struct LibroFmSettingsSheet: View {
    @ObservedObject var viewModel: AudiobooksViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let service = LibroAIService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        if viewModel.isLibroFmConnected {
                            connectedView
                        } else {
                            loginView
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Libro.fm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Connected View
    
    private var connectedView: some View {
        VStack(spacing: 24) {
            // Status card
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                
                Text("Connected to Libro.fm")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                if let email = viewModel.libroFmEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Sign out button
            Button(role: .destructive) {
                Task { await signOut() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.red)
                    }
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.surfaceSecondary)
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)
        }
    }
    
    // MARK: - Login View
    
    private var loginView: some View {
        VStack(spacing: 24) {
            // Info card
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in to your Libro.fm account to browse and download your audiobooks.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                
                Text("Your credentials are sent to the OpenClaw Gateway server which manages the Libro.fm session.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding()
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Form
            VStack(spacing: 16) {
                SettingsTextField(
                    label: "Email",
                    placeholder: "your@email.com",
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                
                SettingsSecureField(
                    label: "Password",
                    placeholder: "Your Libro.fm password",
                    text: $password
                )
                .textContentType(.password)
            }
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Error
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Sign in button
            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSignIn ? Color.anthropicCoral : Color.surfaceSecondary)
                .foregroundStyle(canSignIn ? .white : Color.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSignIn)
        }
    }
    
    // MARK: - Helpers
    
    private var canSignIn: Bool {
        !email.isEmpty && !password.isEmpty && !isLoading
    }
    
    private func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await service.libroFmLogin(email: email, password: password)
            if response.status == "success" {
                await viewModel.checkLibroFmStatus()
                email = ""
                password = ""
            } else {
                errorMessage = response.message ?? "Login failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func signOut() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await service.libroFmLogout()
            await viewModel.checkLibroFmStatus()
            viewModel.libroFmBooks = []
            viewModel.downloadJobs = []
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
