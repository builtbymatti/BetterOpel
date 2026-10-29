// Real driving routes around Rüsselsheim am Main, fetched once from the public
// OSRM demo router and stored as encoded polylines (precision 5).
enum RoutePolylines {
    static let frankfurt = RouteSeed(distanceKm: 25.6, minutes: 25, polyline: #"udcpHk{ir@nD{EqRcnAmO|Csk@}GmS}P}lAs~D}HibAqRyZ_KbJvH{eA{Gw}@asCkqJml@kqF|NuhFyCwd@qRaw@}Yua@crAoWmMqSoQjDme@aRuy@wcAkJvH_DuR"#)
    static let mainz = RouteSeed(distanceKm: 15.8, minutes: 21, polyline: #"udcpHk{ir@~AEnAuEgHyb@mKzB`AnP~UuApI|PnsAaC`AqJ`C`AdJtiDQbt@_C~s@cOhzAsFbTuXjp@cCr[lFt^zu@hkBnEzReD`KgQwBgNzFuZxa@kj@`nAcQtq@uAtOmg@ra@fA|J"#)
    static let wiesbaden = RouteSeed(distanceKm: 19.3, minutes: 23, polyline: #"udcpHk{ir@nD{E{CaN{Cv~AnExb@{IpkBtKxY`Cnl@_a@fwBqmArUecAnr@}Xnr@eNxlBaWzeA_K~H}k@}R}XPc{@rz@ic@vWeNxVsj@|sBiiA~kBgR`AhEfO"#)
    static let heidelberg = RouteSeed(distanceKm: 80.8, minutes: 57, polyline: #"udcpHk{ir@iSsoArlCwyAc@yzC|`FufBrcE_{EnwLe}UvdR~bGljK{q@dcQs{EngE|m@luQwvBf{Ej}Ap{@exE_P_pD"#)
    static let airport = RouteSeed(distanceKm: 15.0, minutes: 17, polyline: #"udcpHk{ir@~AEnAuEqRcnAmO|Csk@}G}H{CoIaLkRkw@qy@gfC}HibAqRyZcGjK{Bg@tHqaASoWiD}^_zBmwHiBaOyHiHkLke@}Hch@s@{TlJmI~AgG}Fgc@"#)
    static let darmstadt = RouteSeed(distanceKm: 29.2, minutes: 29, polyline: #"udcpHk{ir@nD{EaOwaAwH_Fh]?bKfJt@eYvt@ef@j[q`@jNaBmLjAcEwiAbCin@hMcc@hpB_jAlpAwKd^}N|_@ye@d^uhAfVqc@lXmUxt@yUxZeV~Xwh@b}@_xChhAotBbdAs}BjDg@C|GiK{ByDge@`HuiAxR_{@kQmaB`f@uPgAiFuPjDkIyNoKfBuFyq@oSfAeFcr@pReG"#)
}
