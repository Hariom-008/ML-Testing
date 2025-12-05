//
//  StringToURL.swift
//  ByoSync
//
//  Created by Hari's Mac on 31.10.2025.
//

import Foundation
import SwiftUI

func stringToURL(_ text: String) -> URL? {
    if let url = URL(string: text), url.scheme != nil {
        return url
    }
    return nil
}
