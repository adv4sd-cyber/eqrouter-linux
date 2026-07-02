import Foundation

public struct ThirdPartyNotice: Equatable, Identifiable {
    public let name: String
    public let author: String
    public let licenseName: String
    public let summary: String
    public let licenseText: String

    public var id: String { name }

    public init(
        name: String,
        author: String,
        licenseName: String,
        summary: String,
        licenseText: String
    ) {
        self.name = name
        self.author = author
        self.licenseName = licenseName
        self.summary = summary
        self.licenseText = licenseText
    }
}

public enum AboutAppContent {
    public static let correctionSectionAttribution = "Bundled correction library: AutoEq"

    public static let thirdPartyNotices: [ThirdPartyNotice] = [
        ThirdPartyNotice(
            name: "AutoEq",
            author: "Jaakko Pasanen",
            licenseName: "MIT License",
            summary: "Bundled correction profiles are derived from AutoEq. AutoEq aggregates and publishes headphone and earphone EQ results under the MIT License.",
            licenseText: """
            MIT License

            Copyright (c) 2019 Jaakko Pasanen

            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
            """
        )
    ]
}
