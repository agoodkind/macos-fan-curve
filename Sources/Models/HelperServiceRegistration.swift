//
//  HelperServiceRegistration.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-21.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum HelperServiceRegistration {
  static func installOrRepair(
    service: any HelperServiceManaging
  ) -> ManagedServiceMutationResult {
    ManagedService.installOrRepair(helperService: service)
  }
}
