// Local prototype bridge. Keep installed round-dial sessions unchanged; load
// the reviewed Pro protocol only for the explicitly identified test board.
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { homedir } from 'node:os'
import { CableFleet as Fleet } from '../../../../../cli/src/cable/cableFleet.js'
import { CableSession } from '../../../../../cli/src/cable/cableSession.js'
import { findDialPorts } from '../../../../../cli/src/cable/serial.js'

export const PRO_SERIAL = 'E8:F6:0A:E7:64:61'
export const PRO_FLASH_LEASE = join(homedir(), '.harness', 'flasher', 'pro-companion-e8-f6-0a-e7-64-61.lease')
type SessionArgs = ConstructorParameters<typeof CableSession>
class ProSession extends CableSession {
  constructor(host: SessionArgs[0], log: SessionArgs[1], open: SessionArgs[2]) {
    super(new Proxy(host, { get(target, key) {
      // This prototype is flashed deliberately, never by the stock image manifest.
      if (key === 'firmwareFor') return async () => null
      const value = Reflect.get(target, key, target)
      return typeof value === 'function' ? value.bind(target) : value
    } }), log, open)
  }
}
type FleetArgs = ConstructorParameters<typeof Fleet>
export class CableFleet extends Fleet {
  constructor(Session: FleetArgs[0], host: FleetArgs[1], logs: FleetArgs[2], Log: FleetArgs[3], options: FleetArgs[4] = {}) {
    const discover = options.discover ?? findDialPorts
    super(Session, host, logs, Log, { ...options,
      sessionForPort: port => port.serialNumber?.toUpperCase() === PRO_SERIAL ? ProSession : Session,
      discover: async () => {
        const ports = await discover()
        let leased = false
        try {
          const lease = JSON.parse(await readFile(PRO_FLASH_LEASE, 'utf8'))
          leased = lease.serial === PRO_SERIAL && Number.isFinite(lease.until) &&
            lease.until > Date.now() && lease.until < Date.now() + 16 * 60_000
        } catch {}
        return leased ? ports.filter(port => port.serialNumber?.toUpperCase() !== PRO_SERIAL) : ports
      },
    })
  }
}
